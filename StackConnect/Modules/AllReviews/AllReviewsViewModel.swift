import Foundation

// MARK: - Protocol

@MainActor
protocol AllReviewsViewModelProtocol: ObservableObject {
    var uiState: AllReviewsUiState { get set }
    func load() async
    func refresh() async
}

// MARK: - UiState

struct AllReviewsUiState {
    var items: [HomeRecentReview] = []
    var accountsMap: [String: AccountModel] = [:]
    var isLoading = false
}

// MARK: - Implementation

@MainActor
final class AllReviewsViewModel: AllReviewsViewModelProtocol {

    @Published var uiState = AllReviewsUiState()

    private let storage: PersistentStorable
    private let syncService: SyncService

    init(
        storage: PersistentStorable? = nil,
        syncService: SyncService = .shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.syncService = syncService
    }

    /// Loads the reviews already cached on the device. Does not hit the network.
    func load() async {
        uiState.isLoading = true
        defer { uiState.isLoading = false }
        await reload()
    }

    /// Pull-to-refresh: fetch fresh data from the API, then reload from storage.
    func refresh() async {
        await syncService.syncAll(mode: .full).value
        await reload()
    }

    // MARK: - Private

    private func reload() async {
        do {
            let apps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let appById = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
            let reviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)

            uiState.items = reviews
                .compactMap { review -> HomeRecentReview? in
                    guard let appId = review.appId, let app = appById[appId] else { return nil }
                    return HomeRecentReview(review: review, app: app)
                }
                .sorted { (a, b) in
                    (a.review.createdDate ?? .distantPast) > (b.review.createdDate ?? .distantPast)
                }

            uiState.accountsMap = await HomeWidgetDataLoader.loadAccounts(storage: storage)
        } catch {
            Log.print.error("[AllReviews] Failed to load reviews: \(error.localizedDescription)")
            uiState.items = []
        }
    }
}
