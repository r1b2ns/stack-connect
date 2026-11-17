import Foundation

/// Where a dashboard row leads (plan H7): the App Store app detail or the
/// Google Play app detail.
enum DashboardTarget: Hashable {
    case appStore(AppModel)
    case googlePlay(GooglePlayAppItem)
}

/// One ready-to-draw row of the Home In Review / Awaiting Release widgets,
/// provider-neutral (plan H1): App Store rows come from `AppModel` through
/// `AppStatusCategorizer`, Google Play rows from the Play caches. Play apps
/// never become `AppModel`.
struct DashboardEntry: Identifiable, Hashable {
    /// Unique per row (an app can show several: one per platform version or per
    /// Play release).
    let id: String
    let provider: ProviderType
    let accountId: String
    /// App Store app id, or the Play package name.
    let appId: String
    let name: String
    let iconUrl: String?
    let platform: DashboardPlatform?
    /// "In Review", "Production · In review", "Production · Rolling out 20%".
    let statusText: String
    let statusColor: DashboardStatusColor
    /// Version shown in parentheses after the status.
    let versionText: String?
    let progress: DashboardProgress?
    /// Sort key (most recent first); `nil` for Play rows (no date in the API).
    let recency: Date?
    let target: DashboardTarget
    /// The row's account, `nil` only when the accounts couldn't be read (the
    /// row still shows; the tap resolves the account from storage).
    let account: AccountModel?

    var iconURL: URL? {
        iconUrl.flatMap { URL(string: $0) }
    }
}

/// One review row of the Home Recent Reviews widget and All Reviews, for both
/// stores (plan H4).
struct DashboardReview: Identifiable, Hashable {
    let review: CustomerReviewModel
    let provider: ProviderType
    let accountId: String
    /// App Store app id, or the Play package name (`review.appId`).
    let appId: String
    let appName: String
    let iconUrl: String?
    let platform: DashboardPlatform?
    let target: DashboardTarget
    /// `nil` only when the accounts couldn't be read (see `DashboardEntry.account`).
    let account: AccountModel?

    var id: String { "\(provider.rawValue).\(appId).\(review.id)" }

    var iconURL: URL? {
        iconUrl.flatMap { URL(string: $0) }
    }
}

extension DashboardStatusColor {
    init(_ color: AppStoreStateColor) {
        switch color {
        case .green:  self = .green
        case .orange: self = .orange
        case .red:    self = .red
        case .gray:   self = .gray
        case .blue:   self = .blue
        case .yellow: self = .yellow
        }
    }

    /// Lifecycle dot colors of `GooglePlayReleaseLifecycleState.color`.
    init(_ state: GooglePlayReleaseLifecycleState) {
        switch state {
        case .draft, .notSentForReview, .unknown: self = .gray
        case .inReview:                           self = .orange
        case .approvedNotPublished:               self = .yellow
        case .notApproved:                        self = .red
        case .published:                          self = .green
        }
    }
}
