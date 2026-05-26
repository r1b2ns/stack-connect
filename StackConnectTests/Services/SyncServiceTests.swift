import XCTest
@testable import StackConnect

@MainActor
final class SyncServiceTests: XCTestCase {

    private var sut: SyncService!
    private var mockStorage: MockPersistentStorable!
    private var mockKeychain: MockKeyStorable!

    override func setUp() async throws {
        try await super.setUp()
        mockStorage = MockPersistentStorable()
        mockKeychain = MockKeyStorable()
        sut = SyncService(storage: mockStorage, keychain: mockKeychain)
    }

    override func tearDown() async throws {
        sut = nil
        mockStorage = nil
        mockKeychain = nil
        try await super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(sut.state.isSyncing)
        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
        XCTAssertNil(sut.state.lastSyncedAt)
        XCTAssertNil(sut.state.lastError)
    }

    // MARK: - No-op flows

    func testSyncAllWithNoAccountsCompletesAndStampsTimestamp() async {
        await sut.syncAll().value

        XCTAssertFalse(sut.state.isSyncing)
        XCTAssertNotNil(sut.state.lastSyncedAt)
        XCTAssertNil(sut.state.lastError)
        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
    }

    func testSyncAllSkipsNonAppleAccounts() async throws {
        let firebase = AccountModel(name: "Firebase", providerType: .firebase)
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        try await mockStorage.save(firebase, id: firebase.id)
        try await mockStorage.save(play, id: play.id)

        await sut.syncAll().value

        // No SyncMetadata persisted because no Apple account ran
        let metadataFirebase: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(firebase.id)"
        )
        let metadataPlay: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(play.id)"
        )
        XCTAssertNil(metadataFirebase)
        XCTAssertNil(metadataPlay)
        XCTAssertNotNil(sut.state.lastSyncedAt)
    }

    // MARK: - Missing credentials

    func testAppleAccountWithMissingCredentialsRecordsError() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        await sut.syncAll().value

        let metadata: SyncMetadata? = try await mockStorage.fetch(
            SyncMetadata.self, id: "sync.account.\(apple.id)"
        )
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.accountId, apple.id)
        XCTAssertEqual(metadata?.appsSynced, 0)
        XCTAssertNotNil(metadata?.lastError)
    }

    // MARK: - Coalescing

    func testConcurrentSyncAllCallsAreCoalesced() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        let task1 = sut.syncAll()
        let task2 = sut.syncAll()

        await task1.value
        await task2.value

        // One fetch for accounts means only one performSyncAll ran.
        let counts = await mockStorage.fetchAllCallCount
        XCTAssertEqual(counts[String(describing: AccountModel.self)], 1)
    }

    func testSequentialSyncAllCallsBothExecute() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        await sut.syncAll().value
        await sut.syncAll().value

        let counts = await mockStorage.fetchAllCallCount
        XCTAssertEqual(counts[String(describing: AccountModel.self)], 2)
    }

    // MARK: - State transitions

    func testStateClearsAccountsInProgressAfterSync() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await mockStorage.save(apple, id: apple.id)

        await sut.syncAll().value

        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
        XCTAssertFalse(sut.state.isSyncing)
    }
}
