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
    /// Looks up the account's Account Holder and publishes `uiState.agreementShare`
    /// with a prefilled request to accept the pending agreements. Always produces a
    /// payload — falling back to a generic message when the Account Holder can't be
    /// determined — so the share sheet opens either way.
    func prepareAgreementShare(accountId: String) async
}

// MARK: - UiState

struct HomeUiState {
    var providers: [ProviderType] = ProviderType.allCases
    var widgets: [any HomeWidget] = []
    var isLoading = false
    var syncState = SyncState()
    var expiredAccount: AccountModel?
    var showExpiredAlert = false
    var expiringSoonAccount: AccountModel?
    var showExpiringSoonAlert = false
    var pendingAgreementsAccounts: [AccountModel] = []
    /// Accounts whose Account Holder lookup is in flight (drives the share button's
    /// loading/disabled state, per account).
    var preparingAgreementShareAccountIds: Set<String> = []
    /// Non-nil while the "ask the Account Holder" share sheet should be shown.
    /// Cleared by the View when the share sheet is dismissed.
    var agreementShare: AgreementSharePayload?
}

/// One-shot request to present the share sheet asking an account's Account Holder
/// to accept its pending App Store Connect agreements.
struct AgreementSharePayload: Identifiable, Equatable {
    /// Unique per tap, so sharing the same account twice still re-presents.
    let id = UUID()
    let accountId: String
    let message: AgreementShareMessage
}

// MARK: - Implementation

@MainActor
final class HomeViewModel: HomeViewModelProtocol {

    /// Resolves the team-members source for an account, or `nil` when it has no
    /// usable credentials. Injected so tests never hit the network or the keychain.
    typealias TeamUsersFetcherFactory = (AccountModel) -> (any TeamUsersFetching)?

    @Published var uiState = HomeUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let preferences: KeyStorable
    private let syncService: SyncService
    private let teamUsersFetcherFactory: TeamUsersFetcherFactory
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
        syncService: SyncService = .shared,
        teamUsersFetcherFactory: TeamUsersFetcherFactory? = nil
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.preferences = preferences
        self.syncService = syncService
        // Default: the account's real App Store Connect connection, built from its
        // keychain credentials (same path as `UserAccessViewModel`).
        self.teamUsersFetcherFactory = teamUsersFetcherFactory ?? { [keychain] account in
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
                return nil
            }
            return AppleAccountConnection(credentials: credentials)
        }

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

    func prepareAgreementShare(accountId: String) async {
        // Ignore re-taps while this account's lookup is still running.
        guard !uiState.preparingAgreementShareAccountIds.contains(accountId),
              let account = uiState.pendingAgreementsAccounts.first(where: { $0.id == accountId }) else { return }

        uiState.preparingAgreementShareAccountIds.insert(accountId)
        defer { uiState.preparingAgreementShareAccountIds.remove(accountId) }

        // Fetched on every tap on purpose (no caching): users aren't persisted and
        // the Account Holder can change.
        let accountHolder = await fetchAccountHolder(for: account)
        uiState.agreementShare = AgreementSharePayload(
            accountId: accountId,
            message: AgreementShareMessage.make(teamName: account.name, accountHolder: accountHolder)
        )
    }

    /// Returns the team member holding the `ACCOUNT_HOLDER` role, or `nil` when it
    /// can't be determined. Failures are logged, never surfaced: Apple may answer
    /// `/v1/users` with 403 `PLA_NOT_ACCEPTED` while agreements are pending, or the
    /// API key may lack permission to list users — the caller then shares the
    /// generic message instead.
    private func fetchAccountHolder(for account: AccountModel) async -> UserModel? {
        guard let fetcher = teamUsersFetcherFactory(account) else {
            Log.print.error("[Home] No credentials for account \(account.id); sharing the generic agreements request")
            return nil
        }
        do {
            let users = try await fetcher.fetchUsers()
            guard let accountHolder = users.first(where: { $0.roles.contains(UserRoleCatalog.accountHolder) }) else {
                Log.print.info("[Home] No Account Holder among \(users.count) users of account \(account.id); sharing the generic agreements request")
                return nil
            }
            return accountHolder
        } catch {
            Log.print.error("[Home] Account Holder lookup failed for account \(account.id): \(error.localizedDescription)")
            return nil
        }
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
