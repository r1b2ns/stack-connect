import Combine
import Foundation

/// GA4 user properties, for segmenting retention and the activation funnel by
/// account setup (e.g. "do users with a Google Play account churn less?").
///
/// Values are coarse, fixed strings — buckets and `"true"` / `"false"` — never
/// identifiers, names or counts precise enough to fingerprint anyone. Raw values
/// are the names in GA4 (≤ 24 characters, see `FirebaseAnalyticsPayload`):
/// never rename one, the custom dimension is built on it.
enum AnalyticsUserProperty: String, CaseIterable, Sendable {
    /// How many accounts the install has, bucketed: `"0"`, `"1"`, `"2"`, `"3+"`.
    case accountCount = "account_count"
    /// Whether at least one App Store Connect account exists.
    case hasApple = "has_apple"
    /// Whether at least one Firebase account exists.
    case hasFirebase = "has_firebase"
    /// Whether at least one Google Play account exists.
    case hasGooglePlay = "has_google_play"
    /// Whether the user allows notifications (`"true"` / `"false"`), set by
    /// `NotificationPermissionService` at launch, after the permission prompt
    /// and whenever the app becomes active (the user may change it in Settings).
    case notificationsEnabled = "notifications_enabled"

    /// The properties `AnalyticsUserPropertiesUpdater` derives from accounts.
    static let accountDerived: [AnalyticsUserProperty] = [.accountCount, .hasApple, .hasFirebase, .hasGooglePlay]
}

/// Sets user properties. Split from `AnalyticsTracking` (interface
/// segregation): only `AnalyticsUserPropertiesUpdater` needs it, so the many
/// screens and mocks that only track events are unaffected.
@MainActor
protocol AnalyticsUserPropertySetting: AnyObject {
    /// Sets each property when analytics is enabled; dropped otherwise (the
    /// conformer owns the opt-out gate, as for `track`).
    func setUserProperties(_ properties: [AnalyticsUserProperty: String])
}

/// Keeps the account-derived user properties in sync with storage.
///
/// The one place they are computed: once at launch (`start()`, after the
/// SwiftData store is ready) and again on every `accountsDidChange`, which the
/// create, import and delete paths post (`AccountsChange`). Screens never set
/// user properties themselves.
@MainActor
final class AnalyticsUserPropertiesUpdater {

    /// Built on first access, after `StackConnectApp` installed
    /// `SwiftDataStorable.shared`.
    static let shared = AnalyticsUserPropertiesUpdater()

    private let storage: PersistentStorable
    private let analytics: AnalyticsUserPropertySetting
    private let notificationCenter: NotificationCenter
    private var subscription: AnyCancellable?

    /// The refresh started by the last `start()` / account change. Exposed so
    /// tests can await it deterministically.
    private(set) var pendingRefresh: Task<Void, Never>?

    init(
        storage: PersistentStorable? = nil,
        analytics: AnalyticsUserPropertySetting = AnalyticsService.shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.analytics = analytics
        self.notificationCenter = notificationCenter
    }

    /// Computes the properties now and on every later account change.
    /// Calling it again is a no-op for the observation.
    func start() {
        if subscription == nil {
            subscription = notificationCenter.publisher(for: .accountsDidChange)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleRefresh() }
                }
        }
        scheduleRefresh()
    }

    /// Reads every account and sets the properties. A failed read sets
    /// nothing: stale segments are better than a wrong `account_count=0`.
    func refresh() async {
        do {
            let accounts = try await storage.fetchAll(AccountModel.self)
            // A newer refresh superseded this one while it was reading.
            guard !Task.isCancelled else { return }
            analytics.setUserProperties(Self.properties(for: accounts))
        } catch {
            Log.print.error("[Analytics] User properties not updated, accounts unreadable: \(error.localizedDescription)")
        }
    }

    /// The pure mapping, unit tested on its own.
    static func properties(for accounts: [AccountModel]) -> [AnalyticsUserProperty: String] {
        let providers = Set(accounts.map(\.providerType))
        return [
            .accountCount: accountCountBucket(accounts.count),
            .hasApple: String(providers.contains(.apple)),
            .hasFirebase: String(providers.contains(.firebase)),
            .hasGooglePlay: String(providers.contains(.googlePlay))
        ]
    }

    /// `"0"`, `"1"`, `"2"` or `"3+"`: enough to tell single-account users from
    /// power users, coarse enough to stay a handful of GA4 values.
    static func accountCountBucket(_ count: Int) -> String {
        count >= 3 ? "3+" : String(max(count, 0))
    }

    // MARK: - Private

    /// Coalesces bursts ("Delete all accounts" posts once per account): only
    /// the latest refresh is kept, and it reads the final state.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
