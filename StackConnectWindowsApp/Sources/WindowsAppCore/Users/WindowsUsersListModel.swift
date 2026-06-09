import Foundation
import SwiftCrossUI

// T-W08 — Users list model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that provides live-fetch loading
// for the Users tab on the Apps List screen. Fetches account-level team
// members via `AppleConnectionProtocol.fetchUsers()` (account-level — all
// team members; there is no per-app users endpoint).
//
// Mirrors `WindowsAppsListModel` / `WindowsArchivedAppsModel` conventions:
// `@MainActor`, `SwiftCrossUI.ObservableObject`/`@SwiftCrossUI.Published`,
// DI via init (`accountId`, optional `connection: AppleConnectionProtocol?`),
// computed `isEmpty`, async `loadUsers()` that sets isLoading, calls the
// connection, sorts deterministically, and handles failure by setting
// `syncError` (users remain empty or unchanged).
//
// NOTE (reconciliation): The task breakdown mentions a per-app
// `loadUsersForApp(appId:accountId:)`, but the real
// `AppleConnectionProtocol.fetchUsers()` is account-level. This model
// implements an account-level `loadUsers()` per the authoritative D1/D9
// design.

/// Users list model for a single account. Owns the state the
/// `WindowsUsersTabView` binds to and exposes the load intent.
@MainActor
public final class WindowsUsersListModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    /// All team members for the account (active users + pending invitations).
    @SwiftCrossUI.Published public private(set) var users: [UserModel] = []

    /// True while the live fetch is in progress.
    @SwiftCrossUI.Published public private(set) var isLoading: Bool = false

    /// Non-nil when a fetch fails; previous users remain visible (if any).
    @SwiftCrossUI.Published public private(set) var syncError: String? = nil

    // MARK: - Configuration

    /// The account this list displays users for.
    public let accountId: String

    // MARK: - Dependencies

    private let connection: AppleConnectionProtocol?

    // MARK: - Init

    /// Creates a new users list model.
    ///
    /// - Parameters:
    ///   - accountId: The account whose team members to display.
    ///   - connection: Optional Apple connection for live fetch. When nil,
    ///     no fetch is performed and users remain empty (test scenario).
    public init(
        accountId: String,
        connection: AppleConnectionProtocol? = nil
    ) {
        self.accountId = accountId
        self.connection = connection
    }

    // MARK: - Computed Properties

    /// True when no users exist (empty after load or before load).
    public var isEmpty: Bool {
        users.isEmpty
    }

    // MARK: - Load (Live Fetch)

    /// Fetches team members from the live API.
    ///
    /// Users are not cached locally (no offline-first for users in v1), so
    /// the model fetches from the connection each time. If the connection is
    /// nil, the model finishes with empty users (test/offline scenario).
    ///
    /// On success, users are sorted deterministically by `displayName`
    /// (case-insensitive). On failure, `syncError` is set and any previously
    /// loaded users remain visible.
    public func loadUsers() async {
        isLoading = true
        syncError = nil

        // If no connection, finish with empty users.
        guard let connection else {
            isLoading = false
            return
        }

        do {
            let fetched = try await connection.fetchUsers()
            let sorted = fetched.sorted(by: Self.userSortOrder)
            users = sorted
        } catch {
            // On failure: leave existing users unchanged (if any) and set error.
            syncError = "Failed to load users."
        }

        isLoading = false
    }

    // MARK: - Private Helpers

    /// Sort order: case-insensitive alphabetical by `displayName`.
    /// Users with identical display names are disambiguated by id for
    /// deterministic ordering.
    private static func userSortOrder(_ a: UserModel, _ b: UserModel) -> Bool {
        let nameA = a.displayName.lowercased()
        let nameB = b.displayName.lowercased()
        if nameA != nameB { return nameA < nameB }
        return a.id < b.id
    }
}
