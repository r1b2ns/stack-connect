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
    func dismissPendingAgreements(accountId: String)
}

// MARK: - UiState

struct HomeUiState {
    var providers: [ProviderType] = ProviderType.allCases.filter { $0 != .googlePlay }
    var widgets: [any HomeWidget] = []
    var isLoading = false
    var syncState = SyncState()
    var expiredAccount: AccountModel?
    var showExpiredAlert = false
    var expiringSoonAccount: AccountModel?
    var showExpiringSoonAlert = false
    var pendingAgreementsAccounts: [AccountModel] = []
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

    /// Accounts already warned about upcoming expiration this session (avoids repeat alerts).
    private var warnedAccountIds: Set<String> = []

    /// Pending-agreements banners dismissed this session (re-appear next launch if still flagged).
    private var dismissedAgreementAccountIds: Set<String> = []

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
        } else if let expiringSoon = accounts.first(where: { $0.isExpiringSoon && !warnedAccountIds.contains($0.id) }) {
            warnedAccountIds.insert(expiringSoon.id)
            uiState.expiringSoonAccount = expiringSoon
            uiState.showExpiringSoonAlert = true
        }

        // Reuse the same fetch — no extra round-trip — to surface pending-agreements banners.
        uiState.pendingAgreementsAccounts = accounts.filter {
            $0.providerType == .apple
                && $0.hasPendingAgreements
                && !dismissedAgreementAccountIds.contains($0.id)
        }
    }

    // MARK: - Pending Agreements

    func dismissPendingAgreements(accountId: String) {
        dismissedAgreementAccountIds.insert(accountId)
        uiState.pendingAgreementsAccounts.removeAll { $0.id == accountId }
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
