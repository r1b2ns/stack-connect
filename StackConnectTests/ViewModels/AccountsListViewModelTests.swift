import XCTest
@testable import StackConnect

@MainActor
final class AccountsListViewModelTests: XCTestCase {

    private var sut: AccountsListViewModel!
    private var mockStorage: MockPersistentStorable!
    private var mockKeychain: MockKeyStorable!

    override func setUp() async throws {
        try await super.setUp()
        mockStorage = MockPersistentStorable()
        mockKeychain = MockKeyStorable()
        sut = AccountsListViewModel(
            providerType: .apple,
            storage: mockStorage,
            keychain: mockKeychain
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockStorage = nil
        mockKeychain = nil
        try await super.tearDown()
    }

    // MARK: - Load

    func testLoadAccountsFiltersbyProviderType() async throws {
        let apple = AccountModel(name: "Apple Account", providerType: .apple)
        let firebase = AccountModel(name: "Firebase Account", providerType: .firebase)
        try await mockStorage.save(apple, id: apple.id)
        try await mockStorage.save(firebase, id: firebase.id)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.accounts.count, 1)
        XCTAssertEqual(sut.uiState.accounts.first?.name, "Apple Account")
    }

    func testLoadAccountsEmptyState() async {
        await sut.loadAccounts()
        XCTAssertTrue(sut.uiState.accounts.isEmpty)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - Delete

    func testDeleteAccountRemovesFromStorageAndKeychain() async throws {
        let account = AccountModel(name: "ToDelete", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        mockKeychain.set("secret", forKey: "credentials.\(account.id)")

        await sut.loadAccounts()
        XCTAssertEqual(sut.uiState.accounts.count, 1)

        await sut.deleteAccount(at: IndexSet(integer: 0))

        XCTAssertTrue(sut.uiState.accounts.isEmpty)
        XCTAssertNil(mockKeychain.string(forKey: "credentials.\(account.id)"))
    }

    // MARK: - Grouping by team / issuerID (issue #66)

    private func storeAppleCredentials(issuerID: String, for accountId: String) {
        mockKeychain.setObject(
            AppleCredentials(issuerID: issuerID, privateKeyID: "kid", privateKey: "key"),
            forKey: "credentials.\(accountId)"
        )
    }

    func testGroupsSameIssuerIDIntoOneGroup() async throws {
        let a = AccountModel(name: "Team A — Admin", providerType: .apple)
        let b = AccountModel(name: "Team A — Developer", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-shared", for: a.id)
        storeAppleCredentials(issuerID: "issuer-shared", for: b.id)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.count, 1)
        let group = try XCTUnwrap(sut.uiState.groups.first)
        XCTAssertEqual(group.issuerID, "issuer-shared")
        XCTAssertEqual(group.accounts.count, 2)
        // Sorted by name within the group
        XCTAssertEqual(group.accounts.map(\.name), ["Team A — Admin", "Team A — Developer"])
    }

    func testGroupsDifferentIssuerIDsIntoSeparateGroups() async throws {
        let a = AccountModel(name: "Team A", providerType: .apple)
        let b = AccountModel(name: "Team B", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-aaa", for: a.id)
        storeAppleCredentials(issuerID: "issuer-bbb", for: b.id)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.count, 2)
        let issuerIDs = sut.uiState.groups.compactMap(\.issuerID).sorted()
        XCTAssertEqual(issuerIDs, ["issuer-aaa", "issuer-bbb"])
        XCTAssertTrue(sut.uiState.groups.allSatisfy { $0.accounts.count == 1 })
    }

    func testAppleAccountWithoutReadableCredentialsFallsIntoUnknownGroup() async throws {
        let a = AccountModel(name: "Orphan", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        // No credentials stored in keychain → issuerID unreadable.

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.count, 1)
        let group = try XCTUnwrap(sut.uiState.groups.first)
        XCTAssertNil(group.issuerID)
        XCTAssertEqual(group.id, "unknown")
        XCTAssertEqual(group.accounts.first?.name, "Orphan")
    }

    func testShowsTeamGroupsWhenATeamHasMoreThanOneAccount() async throws {
        let a = AccountModel(name: "Team A — Admin", providerType: .apple)
        let b = AccountModel(name: "Team A — Developer", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-shared", for: a.id)
        storeAppleCredentials(issuerID: "issuer-shared", for: b.id)

        await sut.loadAccounts()

        XCTAssertTrue(sut.uiState.showsTeamGroups)
    }

    func testHidesTeamGroupsWhenEveryTeamHasASingleAccount() async throws {
        let a = AccountModel(name: "Team A", providerType: .apple)
        let b = AccountModel(name: "Team B", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-aaa", for: a.id)
        storeAppleCredentials(issuerID: "issuer-bbb", for: b.id)

        await sut.loadAccounts()

        // Two distinct teams, one account each → no team headers.
        XCTAssertFalse(sut.uiState.showsTeamGroups)
    }

    func testDeleteAccountSingleRemovesFromStorageAndKeychainAndRebuildsGroups() async throws {
        let a = AccountModel(name: "Team A", providerType: .apple)
        let b = AccountModel(name: "Team B", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-aaa", for: a.id)
        storeAppleCredentials(issuerID: "issuer-bbb", for: b.id)

        await sut.loadAccounts()
        XCTAssertEqual(sut.uiState.groups.count, 2)

        await sut.deleteAccount(a)

        XCTAssertEqual(sut.uiState.accounts.count, 1)
        XCTAssertEqual(sut.uiState.accounts.first?.name, "Team B")
        XCTAssertNil(mockKeychain.data(forKey: "credentials.\(a.id)"))
        XCTAssertEqual(sut.uiState.groups.count, 1)
        XCTAssertEqual(sut.uiState.groups.first?.issuerID, "issuer-bbb")
    }
}
