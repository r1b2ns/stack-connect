import Foundation
import StackCore

/// What one timeline entry draws: the app's dashboard snapshot plus the cached
/// icon bytes of its rows.
struct WidgetSnapshot: Sendable {
    var dashboard: WidgetDashboardSnapshot
    /// Icon bytes by icon URL (WidgetKit can't fetch remote images at render time).
    var icons: [String: Data] = [:]

    static let empty = WidgetSnapshot(dashboard: .empty)

    func iconData(for url: String?) -> Data? {
        url.flatMap { icons[$0] }
    }
}

/// Reads the snapshot the app writes after each sync (plan H6). Read-only: the
/// widget never hits the network, the Keychain or the app's SwiftData models,
/// and keeps no categorization of its own — both stores follow the in-app Home
/// rules.
enum WidgetDataLoader {

    static func load() -> WidgetSnapshot {
        guard let stored = WidgetDashboardSnapshotStore.load() else {
            Log.print.info("[WidgetExtension] No dashboard snapshot yet")
            return .empty
        }
        let dashboard = SharedFeatureFlags.isGooglePlayAccountsEnabled() ? stored : withoutGooglePlay(stored)
        let urls = dashboard.inReview.compactMap(\.iconUrl)
            + dashboard.awaitingRelease.compactMap(\.iconUrl)
            + dashboard.recentReviews.compactMap(\.iconUrl)
        var icons: [String: Data] = [:]
        for url in Set(urls) {
            icons[url] = WidgetIconCache.iconData(forIconURL: url)
        }
        return WidgetSnapshot(dashboard: dashboard, icons: icons)
    }

    /// Defense in depth while the app's `googlePlayAccounts` flag is OFF: the
    /// app already leaves Google Play out of the snapshot it writes, but a
    /// snapshot written by an earlier launch (flag ON) must not show Android
    /// rows either.
    static func withoutGooglePlay(_ dashboard: WidgetDashboardSnapshot) -> WidgetDashboardSnapshot {
        let inReview = dashboard.inReview.filter { $0.platform != .android }
        let awaiting = dashboard.awaitingRelease.filter { $0.platform != .android }
        return WidgetDashboardSnapshot(
            generatedAt: dashboard.generatedAt,
            inReview: inReview,
            inReviewCount: dashboard.inReviewCount - (dashboard.inReview.count - inReview.count),
            awaitingRelease: awaiting,
            awaitingReleaseCount: dashboard.awaitingReleaseCount - (dashboard.awaitingRelease.count - awaiting.count),
            recentReviews: dashboard.recentReviews.filter { $0.platform != .android }
        )
    }
}
