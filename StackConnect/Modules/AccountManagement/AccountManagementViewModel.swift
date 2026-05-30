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

            // Delete account and credentials
            try await storage.delete(AccountModel.self, id: account.id)
            keychain.removeObject(forKey: "credentials.\(account.id)")
            Log.print.info("[AccountManagement] Deleted account and related data: \(account.name)")
            return true
        } catch {
            Log.print.error("[AccountManagement] Failed to delete account: \(error.localizedDescription)")
            return false
        }
    }
}
