import Foundation
import StackProtocols

/// Sends the activation milestone `first_apps_loaded` once per install: the
/// first time any app list loads with at least one app (Home sync, App Store /
/// Google Play / Firebase app list). It marks the end of onboarding — the user
/// connected an account and saw their apps — so the funnel `create_account` →
/// `first_apps_loaded` shows who never reached value.
///
/// One-shot semantics:
/// - The "reached" flag lives in `UserDefaults` (`sentKey`), so later loads,
///   other screens and additional accounts never send it again.
/// - The flag is set even when analytics is disabled (the event is dropped at
///   the gate): opting in weeks later must not report a "first" load that
///   happened long ago.
/// - Installs that already had cached apps before this event existed are
///   marked without sending (`seedForExistingInstall`), so an app update does
///   not flood the funnel with long-activated users. Every `recordAppsLoaded`
///   waits for that check, so a sync finishing first can't race it.
@MainActor
final class FirstAppsLoadedTracker {

    static let shared = FirstAppsLoadedTracker()

    /// `UserDefaults` key of the one-shot flag.
    static let sentKey = "analytics.firstAppsLoadedSent"

    private let defaults: UserDefaults
    private let analytics: AnalyticsTracking
    private var seedTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, analytics: AnalyticsTracking = AnalyticsService.shared) {
        self.defaults = defaults
        self.analytics = analytics
    }

    /// Whether the milestone was already reached on this install.
    var hasReached: Bool {
        defaults.bool(forKey: Self.sentKey)
    }

    /// Marks the milestone as reached, without sending anything, when the
    /// install already holds apps (App Store apps or a Google Play list) before
    /// any load of this launch. Called once at launch; a no-op once reached.
    func seedForExistingInstall(storage: PersistentStorable) {
        guard !hasReached, seedTask == nil else { return }
        seedTask = Task { [weak self] in
            let hasCachedApps = await Self.hasCachedApps(storage: storage)
            guard let self, hasCachedApps, !self.hasReached else { return }
            self.markReached()
            Log.print.info("[Analytics] first_apps_loaded skipped: apps were cached before this version")
        }
    }

    /// Sends `first_apps_loaded` (`count`, `kind`) the first time a list of at
    /// least one app loaded; does nothing afterwards or for an empty list.
    func recordAppsLoaded(count: Int, provider: ProviderType, on screen: AnalyticsScreen) async {
        await seedTask?.value
        guard count > 0, !hasReached else { return }
        markReached()
        analytics.track(.action(
            .firstAppsLoaded,
            on: screen,
            parameters: [
                AnalyticsParameterKey.count: .int(count),
                AnalyticsParameterKey.kind: .string(provider.rawValue)
            ]
        ))
        Log.print.info("[Analytics] first_apps_loaded reached (\(provider.rawValue), \(count) apps)")
    }

    // MARK: - Private

    private func markReached() {
        defaults.set(true, forKey: Self.sentKey)
    }

    /// Firebase apps are never cached, so only App Store apps and Google Play
    /// lists can reveal an install activated before this event existed.
    private static func hasCachedApps(storage: PersistentStorable) async -> Bool {
        if let apps = try? await storage.fetchAll(AppModel.self), !apps.isEmpty {
            return true
        }
        let playLists = (try? await storage.fetchAll([GooglePlayAppItem].self)) ?? []
        return playLists.contains { !$0.isEmpty }
    }
}
