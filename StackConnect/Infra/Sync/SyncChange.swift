import Foundation

/// Changes detected during a sync that should surface as local "fake push"
/// notifications (status transitions and newly received user reviews).
struct SyncChange: Sendable {

    /// A status as notifications show it, provider-neutral (plan H8): the
    /// App Store state, or the Play track and lifecycle state of a release.
    struct StatusLabel: Hashable, Sendable {
        /// "Ready for Sale", "Production · Approved, not published (2.8.1)".
        let text: String
        let color: DashboardStatusColor

        init(text: String, color: DashboardStatusColor) {
            self.text = text
            self.color = color
        }

        init(appStore state: AppStoreState) {
            self.init(text: state.displayName, color: DashboardStatusColor(state.color))
        }

        init(googlePlay summary: GooglePlayReleaseSummaryModel) {
            let line = GooglePlayTrackStatusLine(track: summary.track, lifecycleState: summary.lifecycleState, versionName: nil)
            self.init(text: "\(line.text) (\(summary.shortName))", color: DashboardStatusColor(summary.lifecycleState))
        }
    }

    /// An app (App Store) or a release (Google Play, `appId` is the package)
    /// whose status changed since the previous sync.
    struct StatusChange: Sendable {
        let accountId: String
        let appId: String
        let appName: String
        let status: StatusLabel
    }

    struct NewReview: Sendable {
        let accountId: String
        let appId: String
        let appName: String
        let reviewId: String
    }

    /// One account leg's app list, loaded successfully (feeds the one-shot
    /// `first_apps_loaded`, see `FirstAppsLoadedTracker`).
    struct LoadedApps: Equatable, Sendable {
        let provider: ProviderType
        let count: Int
    }

    var statusChanges: [StatusChange] = []
    var newReviews: [NewReview] = []
    /// Successful legs, in completion order.
    var loadedApps: [LoadedApps] = []
    /// Accounts whose leg failed (missing credentials, API error). Lets the
    /// run tell a clean sync from one with per-account failures, which are
    /// otherwise only recorded in each account's `SyncMetadata`.
    var failedAccountIds: Set<String> = []
    /// Why each failed leg failed, for the `sync` analytics event (one entry
    /// per failure; never the error's text).
    var failureCategories: [AnalyticsErrorCategory] = []

    /// The result of an account leg that failed: no changes, one failure.
    static func failed(accountId: String, category: AnalyticsErrorCategory = .unknown) -> SyncChange {
        SyncChange(failedAccountIds: [accountId], failureCategories: [category])
    }

    /// The most frequent failure category of the run (ties broken by raw
    /// value, so the result is deterministic); `nil` without failures.
    var dominantFailureCategory: AnalyticsErrorCategory? {
        let counts = Dictionary(failureCategories.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.rawValue > rhs.key.rawValue
        }?.key
    }

    var isEmpty: Bool { statusChanges.isEmpty && newReviews.isEmpty }

    static func + (lhs: SyncChange, rhs: SyncChange) -> SyncChange {
        SyncChange(
            statusChanges: lhs.statusChanges + rhs.statusChanges,
            newReviews: lhs.newReviews + rhs.newReviews,
            loadedApps: lhs.loadedApps + rhs.loadedApps,
            failedAccountIds: lhs.failedAccountIds.union(rhs.failedAccountIds),
            failureCategories: lhs.failureCategories + rhs.failureCategories
        )
    }
}
