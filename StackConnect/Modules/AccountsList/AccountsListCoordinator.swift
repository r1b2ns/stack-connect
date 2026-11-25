import SwiftUI

/// Presentations of the unified accounts list. Navigation to an account's
/// screens goes through the enclosing `HomeCoordinator`.
@MainActor
final class AccountsListCoordinator: ObservableObject {

    /// The wizard on screen (full screen), if any.
    @Published var wizardEntry: AccountWizardEntry?
    /// The expired imported account whose alert is shown.
    @Published var expiredAccount: AccountModel?

    /// Opened once when the list appears (the split view's "Add Account").
    private var pendingEntry: AccountWizardEntry?

    init(initialEntry: AccountWizardEntry? = nil) {
        self.pendingEntry = initialEntry
    }

    func presentWizard(_ entry: AccountWizardEntry) {
        expiredAccount = nil
        wizardEntry = entry
    }

    func dismissWizard() {
        wizardEntry = nil
    }

    func presentExpiredAlert(for account: AccountModel) {
        expiredAccount = account
    }

    /// Presents the initial entry, the first time only.
    func presentInitialEntryIfNeeded() {
        guard let entry = pendingEntry else { return }
        pendingEntry = nil
        presentWizard(entry)
    }
}
