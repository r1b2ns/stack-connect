import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AllReviewsViewModelProtocol: ObservableObject {
    var uiState: AllReviewsUiState { get set }
    func load() async
    func refresh() async
    /// The split view inbox filter: shows `filter` and tracks the change.
    func applyFilter(_ filter: AllReviewsFilter)
}

// MARK: - UiState

/// The reviews of one app, App Store or Google Play (plan S4). The same Play
/// package listed by two accounts is one group (its reviews are cached once,
/// by package).
struct AllReviewsAppGroup: Identifiable, Hashable {
    let provider: ProviderType
    let accountId: String
    /// App Store app id, or the Play package name.
    let appId: String
    let appName: String
    let iconUrl: String?
    let platform: DashboardPlatform?
    let target: DashboardTarget
    let account: AccountModel?
    let reviews: [DashboardReview]

    var id: String { "\(provider.rawValue).\(appId)" }

    var iconURL: URL? {
        iconUrl.flatMap { URL(string: $0) }
    }
}

/// Which reviews the list shows (regular width offers the picker; compact
/// always shows `.all`).
enum AllReviewsFilter: String, CaseIterable, Identifiable {
    case all
    case appStore
    case googlePlay
    case unreplied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:        return String(localized: "All")
        case .appStore:   return String(localized: "App Store")
        case .googlePlay: return String(localized: "Google Play")
        case .unreplied:  return String(localized: "Unreplied", comment: "Reviews filter: reviews without a developer reply.")
        }
    }

    func includes(_ row: DashboardReview) -> Bool {
        switch self {
        case .all:        return true
        case .appStore:   return row.provider == .apple
        case .googlePlay: return row.provider == .googlePlay
        case .unreplied:  return (row.review.responseBody ?? "").isEmpty
        }
    }
}

struct AllReviewsUiState {
    var groups: [AllReviewsAppGroup] = []
    var isLoading = false
    var filter: AllReviewsFilter = .all

    var isEmpty: Bool { groups.isEmpty }

    /// `groups` narrowed by `filter`; groups left without reviews are dropped.
    var visibleGroups: [AllReviewsAppGroup] {
        guard filter != .all else { return groups }
        return groups.compactMap { group in
            let reviews = group.reviews.filter(filter.includes)
            guard !reviews.isEmpty else { return nil }
            return AllReviewsAppGroup(
                provider: group.provider, accountId: group.accountId, appId: group.appId, appName: group.appName,
                iconUrl: group.iconUrl, platform: group.platform, target: group.target, account: group.account,
                reviews: reviews
            )
        }
    }

    /// Reviews without a reply, across every store (the "Unreplied" badge).
    var unrepliedCount: Int {
        groups.reduce(0) { $0 + $1.reviews.filter(AllReviewsFilter.unreplied.includes).count }
    }
}

// MARK: - Implementation

@MainActor
final class AllReviewsViewModel: AllReviewsViewModelProtocol {

    @Published var uiState = AllReviewsUiState()

    private let storage: PersistentStorable
    private let syncService: SyncService
    private let analytics: AnalyticsTracking

    init(
        storage: PersistentStorable? = nil,
        syncService: SyncService = .shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.syncService = syncService
        self.analytics = analytics
    }

    /// Loads the reviews already cached on the device. Does not hit the network.
    func load() async {
        uiState.isLoading = true
        defer { uiState.isLoading = false }
        await reload()
    }

    /// Pull-to-refresh: fetch fresh data from the API, then reload from storage.
    /// Tracked as a `refresh` action with its outcome.
    func refresh() async {
        await syncService.syncAll(mode: .full, trigger: .manual, screen: .allReviews).value
        let reloaded = await reload()
        let succeeded = reloaded && syncService.state.lastError == nil
        analytics.track(.action(.refresh, on: .allReviews, result: succeeded ? .success : .failure))
    }

    /// Local filtering only (no fetch, so no outcome): tracked as a
    /// `filter_reviews` action with the filter as `kind`. Picking the filter
    /// already shown sends nothing.
    func applyFilter(_ filter: AllReviewsFilter) {
        guard filter != uiState.filter else { return }
        uiState.filter = filter
        analytics.track(.action(
            .filterReviews,
            on: .allReviews,
            parameters: [AnalyticsParameterKey.kind: .string(AnalyticsReviewsFilter(filter).rawValue)]
        ))
    }

    // MARK: - Private

    /// Rebuilds the groups from storage. Returns `false` when storage failed.
    ///
    /// Apps of both stores are resolved like the Home Recent Reviews (archived
    /// and orphaned App Store apps dropped, Play apps in scope of accounts that
    /// may view reviews), so a duplicate app id — the same App Store app under
    /// two accounts — never crashes the grouping.
    @discardableResult
    private func reload() async -> Bool {
        do {
            let accountsMap = await HomeWidgetDataLoader.loadAccounts(storage: storage)
            let apps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let active = HomeWidgetDataLoader.filterKnownAccounts(apps.filter { !$0.isArchived }, accountsMap: accountsMap)
            let googlePlay = await HomeWidgetDataLoader.loadGooglePlaySources(
                storage: storage, accounts: accountsMap, requiring: .review, includesReleaseCaches: false
            )
            let reviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)
            let rows = DashboardEntryBuilder.reviews(
                reviews, appStoreApps: active, googlePlaySources: googlePlay, accounts: accountsMap
            )
            uiState.groups = Self.groups(from: rows)
            return true
        } catch {
            Log.print.error("[AllReviews] Failed to load reviews: \(error.localizedDescription)")
            uiState.groups = []
            return false
        }
    }

    /// Rows (newest first) grouped per app; groups ordered by their newest
    /// review, then by name.
    static func groups(from rows: [DashboardReview]) -> [AllReviewsAppGroup] {
        var order: [String] = []
        var byKey: [String: [DashboardReview]] = [:]
        for row in rows {
            let key = "\(row.provider.rawValue).\(row.appId)"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(row)
        }
        return order.compactMap { key -> AllReviewsAppGroup? in
            guard let reviews = byKey[key], let first = reviews.first else { return nil }
            return AllReviewsAppGroup(
                provider: first.provider, accountId: first.accountId, appId: first.appId, appName: first.appName,
                iconUrl: first.iconUrl, platform: first.platform, target: first.target, account: first.account,
                reviews: reviews
            )
        }
        .sorted { a, b in
            let aDate = a.reviews.first?.review.createdDate ?? .distantPast
            let bDate = b.reviews.first?.review.createdDate ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
        }
    }
}
