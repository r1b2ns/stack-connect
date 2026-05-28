import Foundation

@MainActor
protocol AccountManagementViewModelProtocol: ObservableObject {
    var uiState: AccountManagementUiState { get set }
}

struct AccountManagementUiState {
    var account: AccountModel
}

@MainActor
final class AccountManagementViewModel: AccountManagementViewModelProtocol {

    @Published var uiState: AccountManagementUiState

    init(account: AccountModel) {
        self.uiState = AccountManagementUiState(account: account)
    }
}
