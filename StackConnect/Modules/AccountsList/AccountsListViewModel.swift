import Combine
import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AccountsListViewModelProtocol: ObservableObject {
    var uiState: AccountsListUiState { get set }
    func loadAccounts() async
    func deleteAccount(_ account: AccountModel) async
    func clearSearch()
    /// The wizard entry that reconnects the account `accountId` (re-import
    /// deep link), or `nil` when it is gone, hidden or can't be reconnected.
    func reconnectEntry(forAccountId accountId: String) async -> AccountWizardEntry?
}

// MARK: - UiState

/// The unified list's state (shared with Settings › Accounts).
typealias AccountsListUiState = AccountsListingState

// MARK: - Implementation

/// The unified accounts list (plan `unified-accounts.md` §2, Option A): one
/// grouped list for every store, with search.
@MainActor
final class AccountsListViewModel: AccountsListViewModelProtocol {

    @Published var uiState = AccountsListUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking
    private let featureFlags: FeatureFlags
    private let statusProvider: AccountStatusProviding
    private var cancellables = Set<AnyCancellable>()

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        featureFlags: FeatureFlags = .shared,
        statusProvider: AccountStatusProviding? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.storage = storage
        self.keychain = keychain
        self.analytics = analytics
        self.featureFlags = featureFlags
        self.statusProvider = statusProvider ?? AccountStatusService(storage: storage, keychain: keychain)

        // A sign-in expired or works again, or a sync flagged/cleared
        // agreements; or the wizard added, imported or reconnected accounts.
        self.statusProvider.changes
            .merge(with: notificationCenter.publisher(for: .accountsDidChange).map { _ in () }.receive(on: DispatchQueue.main))
            .sink { [weak self] in
                Task { await self?.loadAccounts() }
            }
            .store(in: &cancellables)
    }

    func loadAccounts() async {
        uiState.isLoading = true
        defer {
            uiState.isLoading = false
            uiState.hasLoaded = true
        }
        do {
            uiState.apply(try await AccountsListingSnapshot.load(storage: storage, featureFlags: featureFlags, statusProvider: statusProvider))
        } catch {
            Log.print.error("[AccountsList] Failed to load accounts: \(error.localizedDescription)")
        }
    }

    func clearSearch() {
        uiState.query = ""
    }

    /// Removes the account with its apps, versions, reply templates and
    /// Keychain credentials (`AccountCascadeDeleter`), then reloads.
    func deleteAccount(_ account: AccountModel) async {
        analytics.track(.buttonTap(.delete, on: .accountsList))
        let parameters = [AnalyticsParameterKey.kind: AnalyticsValue.string(account.providerType.rawValue)]
        do {
            try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
            Log.print.info("[AccountsList] Deleted account and related data: \(account.name)")
            analytics.track(.action(.deleteAccount, on: .accountsList, result: .success, parameters: parameters))
        } catch {
            Log.print.error("[AccountsList] Failed to delete account: \(error.localizedDescription)")
            analytics.track(.action(.deleteAccount, on: .accountsList, result: .failure, parameters: parameters))
        }
        await loadAccounts()
    }

    func reconnectEntry(forAccountId accountId: String) async -> AccountWizardEntry? {
        guard let account: AccountModel = try? await storage.fetch(AccountModel.self, id: accountId),
              featureFlags.isVisible(account),
              AccountWizardConfig.canReconnect(account) else { return nil }
        return .reconnect(account)
    }
}
