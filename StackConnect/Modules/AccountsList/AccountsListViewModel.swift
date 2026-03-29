import Foundation

// MARK: - Protocol

@MainActor
protocol AccountsListViewModelProtocol: ObservableObject {
    var uiState: AccountsListUiState { get set }
    func loadAccounts() async
    func deleteAccount(at offsets: IndexSet) async
}

// MARK: - UiState

struct AccountsListUiState {
    var accounts: [AccountModel] = []
    var isLoading = false
    var providerType: ProviderType
}

// MARK: - Implementation

@MainActor
final class AccountsListViewModel: AccountsListViewModelProtocol {

    @Published var uiState: AccountsListUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        providerType: ProviderType,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AccountsListUiState(providerType: providerType)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func loadAccounts() async {
        uiState.isLoading = true
        do {
            let allAccounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            uiState.accounts = allAccounts.filter { $0.providerType == uiState.providerType }
        } catch {
            Log.print.error("[AccountsList] Failed to load accounts: \(error.localizedDescription)")
        }
        uiState.isLoading = false
    }

    func deleteAccount(at offsets: IndexSet) async {
        for index in offsets {
            let account = uiState.accounts[index]
            do {
                try await storage.delete(AccountModel.self, id: account.id)
                keychain.removeObject(forKey: "credentials.\(account.id)")
                Log.print.info("[AccountsList] Deleted account: \(account.name)")
            } catch {
                Log.print.error("[AccountsList] Failed to delete account: \(error.localizedDescription)")
            }
        }
        uiState.accounts.remove(atOffsets: offsets)
    }
}
