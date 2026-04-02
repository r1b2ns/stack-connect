import SwiftUI

final class SettingsAccountsCoordinator: ObservableObject {
    @Published var showAddOptions = false
    @Published var showProviderPicker = false
    @Published var showImport = false
    @Published var selectedProviderType: ProviderType?
    @Published var editingAccount: AccountModel?

    func presentAddOptions() {
        showAddOptions = true
    }

    func presentProviderPicker() {
        showAddOptions = false
        showProviderPicker = true
    }

    func presentImport() {
        showAddOptions = false
        showImport = true
    }

    func presentAddAccount(providerType: ProviderType) {
        showProviderPicker = false
        selectedProviderType = providerType
    }

    func presentEditAccount(_ account: AccountModel) {
        editingAccount = account
    }

    func dismissAddAccount() {
        selectedProviderType = nil
    }

    func dismissEditAccount() {
        editingAccount = nil
    }
}
