import Combine
import Foundation

// MARK: - Protocol

@MainActor
protocol HomeViewModelProtocol: ObservableObject {
    var uiState: HomeUiState { get set }
    func loadDashboard() async
    func triggerSync()
    func refresh() async
    func addWidget(_ kind: HomeWidgetKind)
    func removeWidget(id: UUID)
    func moveWidgets(from source: IndexSet, to destination: Int)
    func availableWidgetKinds() -> [HomeWidgetKind]
    func deleteExpiredAccount(_ account: AccountModel) async
}

// MARK: - UiState

struct HomeUiState {
    var providers: [ProviderType] = ProviderType.allCases.filter { $0 != .googlePlay }
    var widgets: [any HomeWidget] = []
    var isLoading = false
    var syncState = SyncState()
    var expiredAccount: AccountModel?
    var showExpiredAlert = false
}

// MARK: - Implementation

@MainActor
final class HomeViewModel: HomeViewModelProtocol {

    @Published var uiState = HomeUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let preferences: KeyStorable
    private let syncService: SyncService
    private var cancellables = Set<AnyCancellable>()

    private static let widgetsStorageKey = "home.widget.configurations"

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        preferences: KeyStorable = UserDefaultsStorable(),
        syncService: SyncService = .shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.preferences = preferences
        self.syncService = syncService

        loadWidgetConfigurations()

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

        await reloadWidgets()
        await checkExpiredAccounts()
    }

    // MARK: - Account Expiration

    private func checkExpiredAccounts() async {
        let accounts: [AccountModel] = (try? await storage.fetchAll(AccountModel.self)) ?? []
        if let expired = accounts.first(where: { $0.isExpired }) {
            uiState.expiredAccount = expired
            uiState.showExpiredAlert = true
        }
    }

    func deleteExpiredAccount(_ account: AccountModel) async {
        do {
            // Delete all apps belonging to this account, and their versions
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let accountApps = allApps.filter { $0.accountId == account.id }
            for app in accountApps {
                let allVersions: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)
                let appVersions = allVersions.filter { $0.appId == app.id }
                for version in appVersions {
                    try? await storage.delete(AppStoreVersionModel.self, id: "version.\(version.id)")
                }
                try? await storage.delete(AppModel.self, id: "\(account.id).\(app.id)")
            }

            try await storage.delete(AccountModel.self, id: account.id)
            keychain.removeObject(forKey: "credentials.\(account.id)")
            Log.print.info("[Home] Deleted expired account and related data: \(account.name)")
        } catch {
            Log.print.error("[Home] Failed to delete expired account: \(error.localizedDescription)")
        }

        uiState.expiredAccount = nil
        // Surface the next expired account, if any.
        await checkExpiredAccounts()
    }

    // MARK: - Widgets

    func addWidget(_ kind: HomeWidgetKind) {
        guard !uiState.widgets.contains(where: { $0.kind == kind }) else { return }
        let config = HomeWidgetConfiguration(kind: kind)
        let widget = HomeWidgetRegistry.make(for: config, storage: storage)
        uiState.widgets.append(widget)
        saveWidgetConfigurations()
        Task { await widget.load() }
    }

    func removeWidget(id: UUID) {
        uiState.widgets.removeAll { $0.id == id }
        saveWidgetConfigurations()
    }

    func moveWidgets(from source: IndexSet, to destination: Int) {
        uiState.widgets.move(fromOffsets: source, toOffset: destination)
        saveWidgetConfigurations()
    }

    func availableWidgetKinds() -> [HomeWidgetKind] {
        let active = Set(uiState.widgets.map { $0.kind })
        return HomeWidgetKind.allCases.filter { !active.contains($0) }
    }

    private func loadWidgetConfigurations() {
        let configurations: [HomeWidgetConfiguration] = preferences.object(forKey: Self.widgetsStorageKey)
            ?? HomeWidgetRegistry.defaultConfigurations
        uiState.widgets = configurations.map { config in
            HomeWidgetRegistry.make(for: config, storage: storage)
        }
    }

    private func saveWidgetConfigurations() {
        let configurations = uiState.widgets.map { $0.configuration }
        preferences.setObject(configurations, forKey: Self.widgetsStorageKey)
    }

    private func reloadWidgets() async {
        for widget in uiState.widgets {
            await widget.load()
        }
    }
}
