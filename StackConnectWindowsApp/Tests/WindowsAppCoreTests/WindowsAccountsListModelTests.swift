import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsAccountsListModel` (T-F06).
/// Covers: provider filtering, loading state, confirm/cancel delete state
/// transitions, cascade delete execution, and error handling.
@MainActor
final class WindowsAccountsListModelTests: XCTestCase {

    private var storage: MockStorage!
    private var secrets: MockSecrets!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorage()
        secrets = MockSecrets()
    }

    override func tearDown() async throws {
        storage = nil
        secrets = nil
        try await super.tearDown()
    }

    private func makeSUT(provider: ProviderType = .apple) -> WindowsAccountsListModel {
        WindowsAccountsListModel(
            providerType: provider,
            storage: storage,
            secrets: secrets
        )
    }

    // MARK: - Load / Filter by Provider (US-W01)

    func testLoadAccountsFiltersbyProvider() async {
        // Given: two Apple accounts and one Firebase account
        let apple1 = AccountModel(id: "a1", name: "Apple One", providerType: .apple)
        let apple2 = AccountModel(id: "a2", name: "Apple Two", providerType: .apple)
        let firebase = AccountModel(id: "f1", name: "Firebase", providerType: .firebase)
        try! await storage.save(apple1, id: apple1.id)
        try! await storage.save(apple2, id: apple2.id)
        try! await storage.save(firebase, id: firebase.id)

        // When: load with provider = .apple
        let sut = makeSUT(provider: .apple)
        await sut.loadAccounts()

        // Then: only the two Apple accounts appear
        XCTAssertEqual(sut.accounts.count, 2)
        XCTAssertTrue(sut.accounts.allSatisfy { $0.providerType == .apple })
    }

    func testLoadAccountsSetsIsLoadingDuringFetch() async {
        let sut = makeSUT()

        // Before load
        XCTAssertFalse(sut.isLoading)

        // After load completes
        await sut.loadAccounts()
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadAccountsSetsErrorOnFailure() async {
        storage.shouldThrowOnFetch = true
        let sut = makeSUT()

        await sut.loadAccounts()

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.accounts.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Confirm / Cancel Delete State Transitions (US-W06)

    func testConfirmDeleteSetsId() {
        let sut = makeSUT()

        sut.confirmDelete(id: "a1")

        XCTAssertEqual(sut.deleteConfirmingId, "a1")
        XCTAssertNil(sut.errorMessage)
    }

    func testConfirmDeleteClearsExistingError() {
        let sut = makeSUT()
        sut.errorMessage = "old error"

        sut.confirmDelete(id: "a1")

        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(sut.deleteConfirmingId, "a1")
    }

    func testCancelDeleteClearsConfirmingId() {
        let sut = makeSUT()
        sut.confirmDelete(id: "a1")

        sut.cancelDelete()

        XCTAssertNil(sut.deleteConfirmingId)
    }

    // MARK: - Execute Delete Cascade (US-W06 AC-3)

    func testExecuteDeleteRemovesAccountAppsVersionsAndCredentials() async {
        // Given: account with 2 apps, each with 1 version, and a credential
        let account = AccountModel(id: "acc1", name: "Test", providerType: .apple)
        let app1 = AppModel(id: "app1", name: "App 1", bundleId: "com.a1", accountId: "acc1")
        let app2 = AppModel(id: "app2", name: "App 2", bundleId: "com.a2", accountId: "acc1")
        let ver1 = AppStoreVersionModel(id: "v1", appId: "app1")
        let ver2 = AppStoreVersionModel(id: "v2", appId: "app2")

        try! await storage.save(account, id: account.id)
        try! await storage.save(app1, id: "\(account.id).\(app1.id)")
        try! await storage.save(app2, id: "\(account.id).\(app2.id)")
        try! await storage.save(ver1, id: "version.\(ver1.id)")
        try! await storage.save(ver2, id: "version.\(ver2.id)")
        secrets.set("some-key-data", forKey: "credentials.acc1")

        let sut = makeSUT(provider: .apple)
        await sut.loadAccounts()
        XCTAssertEqual(sut.accounts.count, 1)

        // When: confirm + execute delete
        sut.confirmDelete(id: "acc1")
        await sut.executeDelete()

        // Then: account removed from local array
        XCTAssertTrue(sut.accounts.isEmpty)
        XCTAssertNil(sut.deleteConfirmingId)
        XCTAssertNil(sut.errorMessage)

        // Then: versions, apps, account, and credentials deleted from storage
        let remainingVersions: [AppStoreVersionModel] = try! await storage.fetchAll(AppStoreVersionModel.self)
        XCTAssertTrue(remainingVersions.isEmpty)

        let remainingApps: [AppModel] = try! await storage.fetchAll(AppModel.self)
        XCTAssertTrue(remainingApps.isEmpty)

        let remainingAccounts: [AccountModel] = try! await storage.fetchAll(AccountModel.self)
        XCTAssertTrue(remainingAccounts.isEmpty)

        XCTAssertNil(secrets.string(forKey: "credentials.acc1"))
    }

    func testExecuteDeleteFetchesVersionsOnlyOnce() async {
        // Given: account with 3 apps (verifies N+1 fix)
        let account = AccountModel(id: "acc1", name: "Test", providerType: .apple)
        let app1 = AppModel(id: "app1", name: "App 1", bundleId: "com.a1", accountId: "acc1")
        let app2 = AppModel(id: "app2", name: "App 2", bundleId: "com.a2", accountId: "acc1")
        let app3 = AppModel(id: "app3", name: "App 3", bundleId: "com.a3", accountId: "acc1")

        try! await storage.save(account, id: account.id)
        try! await storage.save(app1, id: "\(account.id).\(app1.id)")
        try! await storage.save(app2, id: "\(account.id).\(app2.id)")
        try! await storage.save(app3, id: "\(account.id).\(app3.id)")

        let sut = makeSUT(provider: .apple)
        await sut.loadAccounts()
        sut.confirmDelete(id: "acc1")

        // When
        await sut.executeDelete()

        // Then: AppStoreVersionModel fetchAll was called exactly once (not N times)
        let versionFetchCount = storage.fetchAllCallCount["AppStoreVersionModel"] ?? 0
        XCTAssertEqual(versionFetchCount, 1,
                       "AppStoreVersionModel.fetchAll should be called once, not per-app (N+1 fix)")
    }

    // MARK: - Error Handling (US-W06 AC-5)

    func testExecuteDeleteSetsErrorMessageOnFailure() async {
        // Given: account loaded, but storage throws on delete
        let account = AccountModel(id: "acc1", name: "Test", providerType: .apple)
        try! await storage.save(account, id: account.id)

        let sut = makeSUT(provider: .apple)
        await sut.loadAccounts()
        sut.confirmDelete(id: "acc1")

        // Make storage throw on delete (account delete is not try?)
        storage.shouldThrowOnDelete = true

        // When
        await sut.executeDelete()

        // Then: error message set, account still in list
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(sut.errorMessage, "Failed to delete account. Try again.")
        XCTAssertEqual(sut.accounts.count, 1)
        XCTAssertNil(sut.deleteConfirmingId)
    }

    func testExecuteDeleteWithNoConfirmingIdDoesNothing() async {
        let sut = makeSUT()

        // No confirmDelete called
        await sut.executeDelete()

        XCTAssertNil(sut.errorMessage)
        XCTAssertNil(sut.deleteConfirmingId)
    }
}
