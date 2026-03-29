import SwiftUI

enum AccountsListRoute: Hashable {
    case addAccount(ProviderType)
    case appList(AccountModel)
}

final class AccountsListCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
    @Published var showAddAccount = false

    let providerType: ProviderType

    init(providerType: ProviderType) {
        self.providerType = providerType
    }

    func presentAddAccount() {
        showAddAccount = true
    }

    func navigateToAppList(_ account: AccountModel) {
        path.append(AccountsListRoute.appList(account))
    }
}
