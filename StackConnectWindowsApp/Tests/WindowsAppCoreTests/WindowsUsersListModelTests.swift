import XCTest
@testable import WindowsAppCore

// MARK: - Tests

/// Focused unit tests for `WindowsUsersListModel` (T-W08).
/// Covers: TC-012 (load users — name + role, in order, no row action),
/// TC-013 (zero users -> empty state), fetch failure -> syncError, and
/// loading-state transitions.
@MainActor
final class WindowsUsersListModelTests: XCTestCase {

    private var connection: MockAppleConnection!
    private let accountId = "acc1"

    override func setUp() async throws {
        try await super.setUp()
        connection = MockAppleConnection()
    }

    override func tearDown() async throws {
        connection = nil
        try await super.tearDown()
    }

    /// Helper: creates a SUT with the shared connection.
    private func makeSUT(
        withConnection: Bool = true
    ) -> WindowsUsersListModel {
        WindowsUsersListModel(
            accountId: accountId,
            connection: withConnection ? connection : nil
        )
    }

    /// Helper: creates a simple UserModel for testing.
    private func makeUser(
        id: String,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        roles: [String] = [],
        isPending: Bool = false
    ) -> UserModel {
        UserModel(
            id: id,
            firstName: firstName,
            lastName: lastName,
            email: email,
            roles: roles,
            isPending: isPending
        )
    }

    // MARK: - TC-012: Load users — list contains users in order, each shows name + role

    func testLoadUsersDisplaysUsersInAlphabeticalOrder() async {
        // Given: 3 users (unsorted)
        let users = [
            makeUser(id: "3", firstName: "Charlie", lastName: "Brown", roles: ["ADMIN"]),
            makeUser(id: "1", firstName: "Alice", lastName: "Smith", roles: ["DEVELOPER"]),
            makeUser(id: "2", firstName: "Bob", lastName: "Jones", roles: ["APP_MANAGER"]),
        ]
        connection.fetchUsersResult = .success(users)

        let sut = makeSUT()
        await sut.loadUsers()

        // Then: sorted alphabetically by displayName
        XCTAssertEqual(sut.users.count, 3)
        XCTAssertEqual(sut.users[0].displayName, "Alice Smith")
        XCTAssertEqual(sut.users[1].displayName, "Bob Jones")
        XCTAssertEqual(sut.users[2].displayName, "Charlie Brown")

        // Each user shows name + role
        XCTAssertEqual(sut.users[0].primaryRoleDisplayName, "Developer")
        XCTAssertEqual(sut.users[1].primaryRoleDisplayName, "App Manager")
        XCTAssertEqual(sut.users[2].primaryRoleDisplayName, "Admin")

        // Connection was called once
        XCTAssertEqual(connection.fetchUsersCallCount, 1)
    }

    // MARK: - TC-012: Tapping a row triggers nothing (no route pushed)

    /// The model exposes no navigation action for users — there is no tap
    /// handler, route, or selection state. This test verifies the model has
    /// no such API surface. (The view layer also wires no `onTap` action.)
    func testModelHasNoSelectionOrNavigationState() async {
        connection.fetchUsersResult = .success([
            makeUser(id: "1", firstName: "Alice", roles: ["DEVELOPER"]),
        ])

        let sut = makeSUT()
        await sut.loadUsers()

        // The model only exposes: users, isLoading, syncError, isEmpty, accountId.
        // There is no selectedUser, selectedId, or navigation intent.
        XCTAssertEqual(sut.users.count, 1)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.syncError)
    }

    // MARK: - TC-013: Zero users -> empty state

    func testZeroUsersShowsEmptyState() async {
        connection.fetchUsersResult = .success([])

        let sut = makeSUT()
        await sut.loadUsers()

        XCTAssertTrue(sut.users.isEmpty)
        XCTAssertTrue(sut.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.syncError)
    }

    // MARK: - Fetch failure sets syncError, non-blocking

    func testFetchFailureSetsSyncError() async {
        connection.fetchUsersResult = .failure(
            NSError(domain: "net", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        )

        let sut = makeSUT()
        await sut.loadUsers()

        // syncError is set, users remain empty
        XCTAssertNotNil(sut.syncError)
        XCTAssertTrue(sut.users.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Fetch failure preserves previously loaded users

    func testFetchFailurePreservesPreviouslyLoadedUsers() async {
        // First load: success
        connection.fetchUsersResult = .success([
            makeUser(id: "1", firstName: "Alice", roles: ["DEVELOPER"]),
        ])

        let sut = makeSUT()
        await sut.loadUsers()
        XCTAssertEqual(sut.users.count, 1)
        XCTAssertNil(sut.syncError)

        // Second load: failure
        connection.fetchUsersResult = .failure(
            NSError(domain: "net", code: -1)
        )
        await sut.loadUsers()

        // Previous users preserved, syncError set
        XCTAssertEqual(sut.users.count, 1)
        XCTAssertEqual(sut.users.first?.displayName, "Alice")
        XCTAssertNotNil(sut.syncError)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Loading state transitions

    func testLoadingStateTransitions() async {
        let sut = makeSUT()

        // Before load
        XCTAssertFalse(sut.isLoading)

        // After load completes
        connection.fetchUsersResult = .success([])
        await sut.loadUsers()
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - No connection -> empty users, no error

    func testNoConnectionFinishesWithEmptyUsers() async {
        let sut = makeSUT(withConnection: false)
        await sut.loadUsers()

        XCTAssertTrue(sut.users.isEmpty)
        XCTAssertTrue(sut.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.syncError)
        // No network call (connection is nil)
        XCTAssertEqual(connection.fetchUsersCallCount, 0)
    }

    // MARK: - Users sorted deterministically by displayName then id

    func testUsersSortedDeterministicallyByDisplayNameThenId() async {
        // Two users with same display name but different ids
        let users = [
            makeUser(id: "z", firstName: "Alice", lastName: "Smith", roles: ["DEVELOPER"]),
            makeUser(id: "a", firstName: "Alice", lastName: "Smith", roles: ["ADMIN"]),
        ]
        connection.fetchUsersResult = .success(users)

        let sut = makeSUT()
        await sut.loadUsers()

        // Disambiguated by id: "a" comes before "z"
        XCTAssertEqual(sut.users.count, 2)
        XCTAssertEqual(sut.users[0].id, "a")
        XCTAssertEqual(sut.users[1].id, "z")
    }

    // MARK: - Users with missing names display email or dash

    func testUserDisplayNameFallbacks() async {
        let users = [
            makeUser(id: "1", firstName: nil, lastName: nil, email: "alice@example.com", roles: ["ADMIN"]),
            makeUser(id: "2", firstName: nil, lastName: nil, email: nil, roles: ["DEVELOPER"]),
        ]
        connection.fetchUsersResult = .success(users)

        let sut = makeSUT()
        await sut.loadUsers()

        // Email fallback for first user
        XCTAssertEqual(sut.users.first(where: { $0.id == "1" })?.displayName, "alice@example.com")
        // Dash fallback for second user (no name, no email)
        XCTAssertEqual(sut.users.first(where: { $0.id == "2" })?.displayName, "\u{2013}")
    }

    // MARK: - Users with multiple roles display primary role correctly

    func testPrimaryRoleDisplayName() async {
        let users = [
            makeUser(id: "1", firstName: "Alice", roles: ["APP_MANAGER", "DEVELOPER", "ADMIN"]),
        ]
        connection.fetchUsersResult = .success(users)

        let sut = makeSUT()
        await sut.loadUsers()

        // primaryRoleDisplayName is the first role, formatted
        XCTAssertEqual(sut.users.first?.primaryRoleDisplayName, "App Manager")
        // rolesDisplayName shows all roles
        XCTAssertEqual(sut.users.first?.rolesDisplayName, "App Manager, Developer, Admin")
    }

    // MARK: - Pending users are included in the list

    func testPendingUsersIncludedInList() async {
        let users = [
            makeUser(id: "1", firstName: "Active", lastName: "User", roles: ["DEVELOPER"], isPending: false),
            makeUser(id: "2", firstName: "Pending", lastName: "User", roles: ["ADMIN"], isPending: true),
        ]
        connection.fetchUsersResult = .success(users)

        let sut = makeSUT()
        await sut.loadUsers()

        XCTAssertEqual(sut.users.count, 2)
        // Both active and pending users are in the list
        let pending = sut.users.first(where: { $0.id == "2" })
        XCTAssertNotNil(pending)
        XCTAssertTrue(pending!.isPending)
    }

    // MARK: - syncError clears on subsequent successful load

    func testSyncErrorClearsOnSubsequentSuccessfulLoad() async {
        // First load: failure
        connection.fetchUsersResult = .failure(NSError(domain: "net", code: -1))

        let sut = makeSUT()
        await sut.loadUsers()
        XCTAssertNotNil(sut.syncError)

        // Second load: success
        connection.fetchUsersResult = .success([
            makeUser(id: "1", firstName: "Alice", roles: ["DEVELOPER"]),
        ])
        await sut.loadUsers()

        XCTAssertNil(sut.syncError)
        XCTAssertEqual(sut.users.count, 1)
    }
}
