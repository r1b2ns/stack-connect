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
}
