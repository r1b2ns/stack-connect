import SwiftUI

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
}
