import Foundation
import StackProtocols

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
    private let analytics: AnalyticsTracking

    init(
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = AccountManagementUiState(account: account)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.analytics = analytics
    }

    func deleteAccount() async -> Bool {
        analytics.track(.buttonTap(.confirmDelete, on: .accountManagement))
        let account = uiState.account
        let parameters = [AnalyticsParameterKey.kind: AnalyticsValue.string(account.providerType.rawValue)]
        do {
            try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
            Log.print.info("[AccountManagement] Deleted account and related data: \(account.name)")
            analytics.track(.action(.deleteAccount, on: .accountManagement, result: .success, parameters: parameters))
            return true
        } catch {
            Log.print.error("[AccountManagement] Failed to delete account: \(error.localizedDescription)")
            analytics.track(.action(.deleteAccount, on: .accountManagement, result: .failure, parameters: parameters))
            return false
        }
    }
}
