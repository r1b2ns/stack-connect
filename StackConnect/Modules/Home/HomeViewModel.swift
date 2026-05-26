import Combine
import Foundation

// MARK: - Protocol

@MainActor
protocol HomeViewModelProtocol: ObservableObject {
    var uiState: HomeUiState { get set }
    func loadDashboard() async
    func triggerSync()
    func refresh() async
}

// MARK: - UiState

struct HomeUiState {
    var providers: [ProviderType] = ProviderType.allCases.filter { $0 != .googlePlay }
    var accountsMap: [String: AccountModel] = [:]
    var inReviewApps: [AppModel] = []
    var awaitingReleaseApps: [AppModel] = []
    var phasedByAppId: [String: PhasedReleaseModel] = [:]
    var recentReviews: [HomeRecentReview] = []
    var isLoading = false
    var syncState = SyncState()
}

struct HomeRecentReview: Identifiable, Hashable {
    let review: CustomerReviewModel
    let app: AppModel
    var id: String { review.id }
}

// MARK: - Implementation

@MainActor
final class HomeViewModel: HomeViewModelProtocol {

    @Published var uiState = HomeUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let syncService: SyncService
    private var cancellables = Set<AnyCancellable>()

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        syncService: SyncService = .shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.syncService = syncService

        syncService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                let previousTimestamp = self.uiState.syncState.lastSyncedAt
                self.uiState.syncState = newState
                if newState.lastSyncedAt != previousTimestamp {
                    Task { await self.loadDashboard() }
                }
            }
            .store(in: &cancellables)
    }

    func triggerSync() {
        syncService.syncAll()
    }

    func refresh() async {
        await syncService.syncAll().value
        await loadDashboard()
    }

    func loadDashboard() async {
        uiState.isLoading = true
        defer { uiState.isLoading = false }

        await loadAccountsMap()

        let allApps: [AppModel]
        do {
            allApps = try await storage.fetchAll(AppModel.self)
        } catch {
            Log.print.error("[Home] Failed to load apps: \(error.localizedDescription)")
            return
        }

        let phasedByAppId = await loadPhasedReleases(for: allApps)
        let active = allApps.filter { !$0.isArchived }
        let (inReview, awaitingRelease) = Self.categorize(active, phasedByAppId: phasedByAppId)

        uiState.phasedByAppId = phasedByAppId
        uiState.inReviewApps = inReview.sorted(by: Self.sortByRecency)
        uiState.awaitingReleaseApps = awaitingRelease.sorted(by: Self.sortByRecency)
        uiState.recentReviews = await loadRecentReviews(apps: allApps)
    }

    // MARK: - Private

    private func loadAccountsMap() async {
        do {
            let accounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            var map: [String: AccountModel] = [:]
            for var account in accounts {
                account.fillMissingRules()
                map[account.id] = account
            }
            uiState.accountsMap = map
        } catch {
            Log.print.error("[Home] Failed to load accounts: \(error.localizedDescription)")
        }
    }

    private static func categorize(
        _ apps: [AppModel],
        phasedByAppId: [String: PhasedReleaseModel]
    ) -> (inReview: [AppModel], awaitingRelease: [AppModel]) {
        var inReview: [AppModel] = []
        var awaiting: [AppModel] = []
        for app in apps {
            guard let state = app.appStoreState else { continue }
            switch state {
            case .waitingForReview, .inReview, .readyForReview,
                 .pendingAppleRelease, .processingForAppStore,
                 .rejected, .metadataRejected, .invalidBinary:
                inReview.append(app)
            case .pendingDeveloperRelease:
                awaiting.append(app)
            case .readyForSale:
                // Include in "Awaiting Release" only while phased rollout is in flight.
                if let phased = phasedByAppId[app.id],
                   phased.state == .active || phased.state == .paused {
                    awaiting.append(app)
                }
            default:
                break
            }
        }
        return (inReview, awaiting)
    }

    private func loadPhasedReleases(for apps: [AppModel]) async -> [String: PhasedReleaseModel] {
        var result: [String: PhasedReleaseModel] = [:]
        for app in apps {
            if let phased: PhasedReleaseModel = try? await storage.fetch(PhasedReleaseModel.self, id: "phased.\(app.id)") {
                result[app.id] = phased
            }
        }
        return result
    }

    private func loadRecentReviews(apps: [AppModel]) async -> [HomeRecentReview] {
        let appById = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        do {
            let allReviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)
            return allReviews
                .compactMap { review -> HomeRecentReview? in
                    guard let appId = review.appId, let app = appById[appId] else { return nil }
                    return HomeRecentReview(review: review, app: app)
                }
                .sorted { (a, b) in
                    (a.review.createdDate ?? .distantPast) > (b.review.createdDate ?? .distantPast)
                }
                .prefix(10)
                .map { $0 }
        } catch {
            Log.print.error("[Home] Failed to load reviews: \(error.localizedDescription)")
            return []
        }
    }

    private static func sortByRecency(_ a: AppModel, _ b: AppModel) -> Bool {
        switch (a.lastModifiedDate, b.lastModifiedDate) {
        case let (dateA?, dateB?): return dateA > dateB
        case (_?, nil):            return true
        case (nil, _?):            return false
        case (nil, nil):           return a.name < b.name
        }
    }
}
