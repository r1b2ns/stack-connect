import Foundation

extension Notification.Name {
    /// Posted after an account was created, imported or deleted. Carries no
    /// object: observers re-read the accounts from storage.
    static let accountsDidChange = Notification.Name("StackConnect.accountsDidChange")
}

/// The single "the set of accounts changed" signal.
///
/// Posted by the three places that add or remove an `AccountModel` —
/// `AddAccountViewModel` (create), `AccountImporter` (import / re-import) and
/// `AccountCascadeDeleter` (every delete path, "Delete all accounts" included) —
/// so derived state such as the analytics user properties
/// (`AnalyticsUserPropertiesUpdater`) never has to be wired into each screen.
enum AccountsChange {
    static func post(center: NotificationCenter = .default) {
        center.post(name: .accountsDidChange, object: nil)
    }
}
