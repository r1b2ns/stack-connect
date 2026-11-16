import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AllReviewsViewModelProtocol: ObservableObject {
    var uiState: AllReviewsUiState { get set }
    func load() async
    func refresh() async
}

// MARK: - UiState

struct AllReviewsAppGroup: Identifiable, Hashable {
    let app: AppModel
    let account: AccountModel
    let reviews: [CustomerReviewModel]

    var id: String { app.id }
}

struct AllReviewsUiState {
    var groups: [AllReviewsAppGroup] = []
    var isLoading = false

    var isEmpty: Bool { groups.isEmpty }
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
        await syncService.syncAll(mode: .full).value
        let reloaded = await reload()
        let succeeded = reloaded && syncService.state.lastError == nil
        analytics.track(.action(.refresh, on: .allReviews, result: succeeded ? .success : .failure))
    }

    // MARK: - Private

    /// Rebuilds the groups from storage. Returns `false` when storage failed.
    @discardableResult
    private func reload() async -> Bool {
        do {
            let apps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let appById = Dictionary(uniqueKeysWithValues: apps.filter { !$0.isArchived }.map { ($0.id, $0) })
            let reviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)
            let accountsMap = await HomeWidgetDataLoader.loadAccounts(storage: storage)

            let reviewsByApp = Dictionary(grouping: reviews) { $0.appId }

            uiState.groups = reviewsByApp
                .compactMap { appId, appReviews -> AllReviewsAppGroup? in
                    guard let appId, let app = appById[appId] else { return nil }
                    let sorted = appReviews.sorted { (a, b) in
                        (a.createdDate ?? .distantPast) > (b.createdDate ?? .distantPast)
                    }
                    return AllReviewsAppGroup(
                        app: app,
                        account: HomeWidgetDataLoader.account(for: app, in: accountsMap),
                        reviews: sorted
                    )
                }
                .sorted { (a, b) in
                    let aDate = a.reviews.first?.createdDate ?? .distantPast
                    let bDate = b.reviews.first?.createdDate ?? .distantPast
                    if aDate != bDate { return aDate > bDate }
                    return a.app.name.localizedCaseInsensitiveCompare(b.app.name) == .orderedAscending
                }
            return true
        } catch {
            Log.print.error("[AllReviews] Failed to load reviews: \(error.localizedDescription)")
            uiState.groups = []
            return false
        }
    }
}
