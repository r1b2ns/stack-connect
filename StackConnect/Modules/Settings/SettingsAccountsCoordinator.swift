import SwiftUI

/// Presentations of Settings › Accounts. Pushing an account's detail goes
/// through the enclosing `HomeCoordinator`.
@MainActor
final class SettingsAccountsCoordinator: ObservableObject {

    /// The wizard on screen (full screen), if any.
    @Published var wizardEntry: AccountWizardEntry?

    /// "Add account" (Type step), "Import .scexport file", or a store's "Add".
    func presentWizard(_ entry: AccountWizardEntry) {
        wizardEntry = entry
    }

    func dismissWizard() {
        wizardEntry = nil
    }
}
