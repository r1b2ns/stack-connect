import Foundation

@MainActor
protocol AccountManagementViewModelProtocol: ObservableObject {
    var uiState: AccountManagementUiState { get set }
    func deleteAccount() async -> Bool
}

struct AccountManagementUiState {
    var account: AccountModel
    var showDeleteConfirmation = false
}

@MainActor
final class AccountManagementViewModel: AccountManagementViewModelProtocol {

    @Published var uiState: AccountManagementUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AccountManagementUiState(account: account)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func deleteAccount() async -> Bool {
        let account = uiState.account
        do {
            try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
            Log.print.info("[AccountManagement] Deleted account and related data: \(account.name)")
            return true
        } catch {
            Log.print.error("[AccountManagement] Failed to delete account: \(error.localizedDescription)")
            return false
        }
    }
}
