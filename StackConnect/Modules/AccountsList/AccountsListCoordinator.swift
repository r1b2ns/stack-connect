import SwiftUI

final class AccountsListCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
    @Published var showAddOptions = false
    @Published var showAddAccount = false
    @Published var showImport = false

    let providerType: ProviderType

    init(providerType: ProviderType) {
        self.providerType = providerType
    }

    func presentAddOptions() {
        showAddOptions = true
    }

    func presentAddAccount() {
        showAddOptions = false
        showAddAccount = true
    }

    func presentImport() {
        showAddOptions = false
        showImport = true
    }
}
