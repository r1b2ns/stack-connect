import XCTest
import StackProtocols
@testable import StackHomeCore

/// Core-side pipeline tests for the extracted `SyncService`: coalescing
/// (TC-018/TC-078) and the state transitions that feed the banner
/// (US-003/US-004, TC-012/TC-013). The exhaustive under-gating suite is the
/// formal T-E2 task; these guard the semantics that the extraction must
/// preserve so the iOS wrapper and the existing `SyncServiceTests` stay green.
@MainActor
final class SyncServiceTests: XCTestCase {

    private struct StubCredentials: Codable, Sendable {
        let issuerID: String
    }

    private var storage: InMemoryStorage!
    private var keychain: InMemoryKeychain!
    private var connections: [String: StubSyncing] = [:]
    private var sut: SyncService<StubCredentials>!

    override func setUp() async throws {
        try await super.setUp()
        storage = InMemoryStorage()
        keychain = InMemoryKeychain()
        connections = [:]
        sut = SyncService(
            storage: storage,
            keychain: keychain,
            appleConnectionFactory: { [connections] creds in
                connections[creds.issuerID] ?? StubSyncing()
            }
        )
    }

    override func tearDown() async throws {
        sut = nil
        storage = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Coalescing (TC-018 / TC-078)

    func testConcurrentSyncAllCallsAreCoalesced() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await storage.save(apple, id: apple.id)

        let task1 = sut.syncAll()
        let task2 = sut.syncAll()
        await task1.value
        await task2.value

        // One accounts fetch == only one performSyncAll ran (no duplicate sync).
        XCTAssertEqual(storage.fetchAllCount(for: AccountModel.self), 1)
    }

    func testSequentialSyncAllCallsBothExecute() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await storage.save(apple, id: apple.id)

        await sut.syncAll().value
        await sut.syncAll().value

        XCTAssertEqual(storage.fetchAllCount(for: AccountModel.self), 2)
    }

    // MARK: - State transitions (US-003/US-004, TC-012/TC-013)

    func testStateTransitionsIdleToSyncingToIdle() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await storage.save(apple, id: apple.id)
        setCredentials(issuerID: "issuer-1", for: apple)
        connections["issuer-1"] = StubSyncing()

        XCTAssertFalse(sut.state.isSyncing)

        var observed: [Bool] = []
        sut.onStateChanged = { observed.append($0.isSyncing) }

        await sut.syncAll().value

        XCTAssertFalse(sut.state.isSyncing)
        XCTAssertNotNil(sut.state.lastSyncedAt)
        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
        // Must have flipped to syncing and back to idle.
        XCTAssertTrue(observed.contains(true), "expected an isSyncing=true transition")
        XCTAssertEqual(observed.last, false, "must settle back to idle")
    }

    /// TC-012: while a sync runs, the in-progress account count surfaces a
    /// "Syncing N…" banner. The count is `accountsInProgress.count`.
    func testInProgressCountReflectsActiveAccounts() async throws {
        let a = AccountModel(name: "A", providerType: .apple)
        let b = AccountModel(name: "B", providerType: .apple)
        try await storage.save(a, id: a.id)
        try await storage.save(b, id: b.id)
        setCredentials(issuerID: "issuer-A", for: a)
        setCredentials(issuerID: "issuer-B", for: b)
        connections["issuer-A"] = StubSyncing()
        connections["issuer-B"] = StubSyncing()

        var maxInProgress = 0
        sut.onStateChanged = { maxInProgress = max(maxInProgress, $0.accountsInProgress.count) }

        await sut.syncAll().value

        XCTAssertGreaterThanOrEqual(maxInProgress, 1,
            "at least one account should be reported in progress (Syncing N…)")
        XCTAssertTrue(sut.state.accountsInProgress.isEmpty,
            "in-progress set must clear after sync (banner returns to idle)")
    }

    /// TC-013: with zero Apple accounts the sync completes with an empty
    /// in-progress set (banner shows "Syncing…" with no count, then idle).
    func testNoAppleAccountsKeepsInProgressEmpty() async throws {
        let firebase = AccountModel(name: "FB", providerType: .firebase)
        try await storage.save(firebase, id: firebase.id)

        await sut.syncAll().value

        XCTAssertTrue(sut.state.accountsInProgress.isEmpty)
        XCTAssertFalse(sut.state.isSyncing)
        XCTAssertNotNil(sut.state.lastSyncedAt)
    }

    // MARK: - AsyncStream

    func testStatesStreamReplaysCurrentAndYieldsTransitions() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await storage.save(apple, id: apple.id)
        setCredentials(issuerID: "issuer-1", for: apple)
        connections["issuer-1"] = StubSyncing()

        var iterator = sut.states.makeAsyncIterator()
        // Replays the current (idle) state immediately.
        let first = await iterator.next()
        XCTAssertEqual(first?.isSyncing, false)

        await sut.syncAll().value

        // Drain a few yielded transitions and confirm a syncing=true appeared.
        var sawSyncing = false
        for _ in 0..<4 {
            if let next = await iterator.next(), next.isSyncing { sawSyncing = true; break }
        }
        XCTAssertTrue(sawSyncing, "stream must yield an isSyncing=true transition")
    }

    // MARK: - Side effects hook

    func testSideEffectsAreInvoked() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        try await storage.save(apple, id: apple.id)
        setCredentials(issuerID: "issuer-1", for: apple)
        connections["issuer-1"] = StubSyncing()

        let effects = SpySideEffects()
        let service = SyncService<StubCredentials>(
            storage: storage,
            keychain: keychain,
            appleConnectionFactory: { [connections] creds in connections[creds.issuerID] ?? StubSyncing() },
            sideEffects: effects
        )

        await service.syncAll(mode: .lightweight).value

        let started = await effects.didStart
        let finished = await effects.didFinish
        XCTAssertTrue(started, "syncDidStart must fire for a non-empty account set")
        XCTAssertTrue(finished, "syncDidFinish must fire after persistence")
    }

    // MARK: - Helpers

    private func setCredentials(issuerID: String, for account: AccountModel) {
        keychain.setObject(StubCredentials(issuerID: issuerID), forKey: "credentials.\(account.id)")
    }
}

// MARK: - Test doubles

private actor SpySideEffects: SyncSideEffects {
    private(set) var didStart = false
    private(set) var didFinish = false
    func syncDidStart(mode: SyncMode, accountCount: Int) async { didStart = true }
    func syncDidFinish(mode: SyncMode, changes: SyncChange) async { didFinish = true }
}

private final class StubSyncing: AppleAccountSyncing, @unchecked Sendable {
    var apps: [AppInfo] = []
    func fetchApps() async throws -> [AppInfo] { apps }
    func fetchIconUrl(appId: String) async -> String? { nil }
    func fetchAppStoreVersions(appId: String, limit: Int) async throws -> [AppStoreVersionModel] { [] }
    func fetchRecentReviews(appId: String, limit: Int) async throws -> [CustomerReviewModel] { [] }
    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel? { nil }
}

/// Minimal in-memory `PersistentStorable` for the core pipeline tests.
/// Lock-guarded class (not an actor) so `fetchAllCount` can be read
/// synchronously after the awaited sync completes.
private final class InMemoryStorage: PersistentStorable, @unchecked Sendable {
    private var store: [String: Data] = [:]
    private var fetchAllCounts: [String: Int] = [:]
    private let lock = NSLock()

    func save<T: Codable>(_ item: T, id: String) async throws {
        let data = try JSONEncoder().encode(item)
        lock.lock(); defer { lock.unlock() }
        store["\(String(describing: T.self)).\(id)"] = data
    }

    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? {
        lock.lock()
        let data = store["\(String(describing: T.self)).\(id)"]
        lock.unlock()
        guard let data else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
        let key = String(describing: T.self)
        lock.lock()
        fetchAllCounts[key, default: 0] += 1
        let datas = store.filter { $0.key.hasPrefix("\(key).") }.values
        lock.unlock()
        return try datas.map { try JSONDecoder().decode(T.self, from: $0) }
    }

    func delete<T: Codable>(_ type: T.Type, id: String) async throws {
        lock.lock(); defer { lock.unlock() }
        store["\(String(describing: T.self)).\(id)"] = nil
    }

    func deleteAll<T: Codable>(_ type: T.Type) async throws {
        lock.lock(); defer { lock.unlock() }
        let prefix = "\(String(describing: T.self))."
        for key in store.keys where key.hasPrefix(prefix) { store[key] = nil }
    }

    func fetchAllCount(for type: (some Codable).Type) -> Int {
        lock.lock(); defer { lock.unlock() }
        return fetchAllCounts[String(describing: type)] ?? 0
    }
}

/// Minimal in-memory `KeyStorable` for the core pipeline tests.
private final class InMemoryKeychain: KeyStorable, @unchecked Sendable {
    private var store: [String: Data] = [:]
    private let lock = NSLock()

    func string(forKey key: String) -> String? { nil }
    func int(forKey key: String) -> Int? { nil }
    func double(forKey key: String) -> Double? { nil }
    func bool(forKey key: String) -> Bool? { nil }
    func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return store[key]
    }
    func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        store[key] = value as? Data
    }
    func removeObject(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        store[key] = nil
    }
}
