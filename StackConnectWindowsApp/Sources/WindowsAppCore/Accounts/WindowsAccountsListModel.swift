import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

// Phase 4 · Block F · T-F06 — Accounts list model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that loads accounts filtered by
// provider, exposes loading/error/delete-confirmation state, and handles the
// cascade-delete flow (account + apps + versions + credentials).
//
// Mirrors the iOS `AccountsListViewModel` pattern but adapted to SwiftCrossUI's
// `ObservableObject`/`@Published` and the Windows persistence backends
// (`SQLitePersistentStorable` + `WindowsCredentialStorable`).

/// Accounts list model for a single provider type. Owns the state the
/// `WindowsAccountsListView` binds to and exposes intents for loading,
/// confirming, and executing account deletion.
@MainActor
public final class WindowsAccountsListModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    /// Accounts filtered by the configured `providerType`.
    @SwiftCrossUI.Published public private(set) var accounts: [AccountModel] = []

    /// True while a fetch is in progress.
    @SwiftCrossUI.Published public private(set) var isLoading: Bool = false

    /// When non-nil, the inline confirmation banner is shown for this account id.
    @SwiftCrossUI.Published public var deleteConfirmingId: String? = nil

    /// When non-nil, an inline error banner is shown with this message.
    @SwiftCrossUI.Published public var errorMessage: String? = nil

    // MARK: - Configuration

    /// The provider type this list displays.
    public let providerType: ProviderType

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let secrets: KeyStorable

    // MARK: - Init

    public init(
        providerType: ProviderType,
        storage: PersistentStorable,
        secrets: KeyStorable
    ) {
        self.providerType = providerType
        self.storage = storage
        self.secrets = secrets
    }

    // MARK: - Load

    /// Fetches all accounts from the SQLite store, filters by `providerType`, and
    /// fills missing rules for created accounts. Clears the loading flag on
    /// completion regardless of success or failure.
    public func loadAccounts() async {
        isLoading = true
        do {
            var allAccounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            for i in allAccounts.indices {
                allAccounts[i].fillMissingRules()
            }
            accounts = allAccounts.filter { $0.providerType == providerType }
        } catch {
            errorMessage = "Failed to load accounts."
        }
        isLoading = false
    }

    // MARK: - Delete Flow

    /// Shows the inline confirmation banner for the given account id (US-W06 AC-2).
    public func confirmDelete(id: String) {
        errorMessage = nil
        deleteConfirmingId = id
    }

    /// Dismisses the confirmation banner without deleting (US-W06 AC-4).
    public func cancelDelete() {
        deleteConfirmingId = nil
    }

    /// Executes the cascade delete for the account currently held in
    /// `deleteConfirmingId` (US-W06 AC-3):
    ///
    /// 1. Fetches all apps and versions in bulk (single query each).
    /// 2. Removes all `AppStoreVersionModel` entries for the account's apps.
    /// 3. Removes all `AppModel` entries belonging to the account.
    /// 4. Removes the `AccountModel` itself.
    /// 5. Removes the credentials from the secret store.
    ///
    /// On failure, sets `errorMessage` and leaves the account intact (AC-5).
    public func executeDelete() async {
        guard let accountId = deleteConfirmingId else { return }
        guard let account = accounts.first(where: { $0.id == accountId }) else {
            deleteConfirmingId = nil
            return
        }

        do {
            // 1. Fetch all apps and versions in bulk (avoids N+1 queries)
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let accountApps = allApps.filter { $0.accountId == account.id }
            let allVersions: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)

            // 2. Delete all versions belonging to this account's apps
            for app in accountApps {
                let appVersions = allVersions.filter { $0.appId == app.id }
                for version in appVersions {
                    try? await storage.delete(AppStoreVersionModel.self, id: "version.\(version.id)")
                }
                // 3. Delete the app
                try? await storage.delete(AppModel.self, id: "\(account.id).\(app.id)")
            }

            // 4. Delete the account
            try await storage.delete(AccountModel.self, id: account.id)

            // 5. Remove credentials from the secret store
            secrets.removeObject(forKey: "credentials.\(account.id)")

            // Success: remove from local array and clear confirmation state
            accounts.removeAll { $0.id == accountId }
            deleteConfirmingId = nil
            errorMessage = nil
        } catch {
            // US-W06 AC-5: show error, account remains
            deleteConfirmingId = nil
            errorMessage = "Failed to delete account. Try again."
        }
    }
}
