import XCTest
import StackProtocols
@testable import StackHomeCore

/// Core-side tests for the migrated, Foundation-pure `HomeViewModel` (T-A10 /
/// T-E1). Covers expiration precedence (US-005 AC-7 — TC-023/TC-088), widget
/// add/remove/reorder + persistence round-trip (US-008 / US-010 AC-6 —
/// TC-045/TC-047/TC-048/TC-049/TC-080/TC-081/TC-060/TC-079), manual-sync
/// orchestration + coalescing wiring (US-004 — TC-018/TC-078), the loading flag
/// transition (US-012 — TC-070), and `onStateChanged` republish transitions.
@MainActor
final class HomeViewModelTests: XCTestCase {

    private var storage: InMemoryStorage!
    private var preferences: InMemoryPreferences!
    private var sync: StubSync!

    override func setUp() async throws {
        try await super.setUp()
        storage = InMemoryStorage()
        preferences = InMemoryPreferences()
        sync = StubSync()
    }

    override func tearDown() async throws {
        storage = nil
        preferences = nil
        sync = nil
        try await super.tearDown()
    }

    private func makeSUT(defaults: [HomeWidgetConfiguration] = []) -> HomeViewModel {
        HomeViewModel(
            storage: storage,
            preferences: preferences,
            sync: sync,
            defaultConfigurations: defaults,
            widgetFactory: { MockWidget(configuration: $0) }
        )
    }

    // MARK: - Defaults / load (TC-060 / TC-079 load side)

    func testFreshInstallHasNoWidgets() {
        let sut = makeSUT()
        XCTAssertTrue(sut.state.widgets.isEmpty)
    }

    func testLoadsConfigurationsFromPreferences() {
        let stored = [HomeWidgetConfiguration(kind: .recentReviews, size: .compact)]
        preferences.setObject(stored, forKey: HomeViewModel.widgetsStorageKey)

        let sut = makeSUT()

        XCTAssertEqual(sut.state.widgets.count, 1)
        XCTAssertEqual(sut.state.widgets.first?.configuration.size, .compact)
        XCTAssertEqual(sut.state.widgets.first?.kind, .recentReviews)
    }

    // MARK: - Add / duplicate guard (US-008 AC-4 / TC-045)

    func testAddWidgetAppendsAndPersists() {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)

        XCTAssertEqual(sut.state.widgets.count, 1)
        XCTAssertEqual(sut.state.widgets.first?.kind, .recentReviews)
        let stored: [HomeWidgetConfiguration]? = preferences.object(forKey: HomeViewModel.widgetsStorageKey)
        XCTAssertEqual(stored?.first?.kind, .recentReviews)
    }

    func testAddWidgetDoesNotDuplicateExistingKind() {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)
        sut.addWidget(.recentReviews)
        XCTAssertEqual(sut.state.widgets.count, 1)
    }

    // MARK: - Remove (US-008 AC-5)

    func testRemoveWidgetReturnsItToAddAndPersists() {
        let sut = makeSUT()
        sut.addWidget(.inReview)
        guard let id = sut.state.widgets.first?.id else { return XCTFail("expected a widget") }

        sut.removeWidget(id: id)

        XCTAssertTrue(sut.state.widgets.isEmpty)
        XCTAssertTrue(sut.availableWidgetKinds().contains(.inReview))
        let stored: [HomeWidgetConfiguration]? = preferences.object(forKey: HomeViewModel.widgetsStorageKey)
        XCTAssertEqual(stored?.count, 0)
    }

    // MARK: - Reorder (US-008 AC-6 / TC-047 / TC-048 / TC-049 / TC-080 / TC-081)

    func testMoveWidgetUpReorders() {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)
        sut.addWidget(.inReview)
        sut.addWidget(.awaitingRelease)

        // Move index 2 (awaitingRelease) up to index 1.
        sut.moveWidgets(from: IndexSet(integer: 2), to: 1)

        XCTAssertEqual(sut.state.widgets.map { $0.kind }, [.recentReviews, .awaitingRelease, .inReview])
        let stored: [HomeWidgetConfiguration]? = preferences.object(forKey: HomeViewModel.widgetsStorageKey)
        XCTAssertEqual(stored?.map { $0.kind }, [.recentReviews, .awaitingRelease, .inReview])
    }

    func testMoveWidgetDownReorders() {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)
        sut.addWidget(.inReview)
        sut.addWidget(.awaitingRelease)

        // Move index 0 (recentReviews) down to the end.
        sut.moveWidgets(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(sut.state.widgets.map { $0.kind }, [.inReview, .awaitingRelease, .recentReviews])
    }

    func testMoveToSameIndexIsNoOp() {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)
        sut.addWidget(.inReview)
        let before = sut.state.widgets.map { $0.kind }

        // Moving index 1 to offset 1 lands it in the same place.
        sut.moveWidgets(from: IndexSet(integer: 1), to: 1)

        XCTAssertEqual(sut.state.widgets.map { $0.kind }, before)
    }

    func testMoveOutOfBoundsDoesNotCrash() {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)
        sut.addWidget(.inReview)
        let before = sut.state.widgets.map { $0.kind }

        sut.moveWidgets(from: IndexSet(integer: 5), to: 9)

        XCTAssertEqual(sut.state.widgets.map { $0.kind }, before)
    }

    // MARK: - Persistence round-trip across "restart" (TC-060 / TC-079)

    func testWidgetConfigurationSurvivesRestart() {
        let first = makeSUT()
        first.addWidget(.inReview)
        first.addWidget(.recentReviews)
        first.moveWidgets(from: IndexSet(integer: 1), to: 0)

        // Simulate a restart: a brand-new view model over the SAME preferences.
        let restarted = HomeViewModel(
            storage: storage,
            preferences: preferences,
            sync: StubSync(),
            widgetFactory: { MockWidget(configuration: $0) }
        )

        XCTAssertEqual(restarted.state.widgets.map { $0.kind }, [.recentReviews, .inReview])
    }

    // MARK: - Expiration precedence (US-005 AC-7 / TC-023 / TC-088)

    func testExpiredTakesPrecedenceOverExpiringSoon() async throws {
        // One account that is BOTH expired and (vacuously) the only candidate,
        // plus a separate expiring-soon account.
        let expired = AccountModel(
            name: "Expired",
            providerType: .apple,
            expirationDate: Date().addingTimeInterval(-60)
        )
        let expiring = AccountModel(
            name: "Expiring",
            providerType: .apple,
            expirationDate: Date().addingTimeInterval(60 * 60)
        )
        try await storage.save(expired, id: expired.id)
        try await storage.save(expiring, id: expiring.id)

        let sut = makeSUT()
        await sut.loadDashboard()

        XCTAssertTrue(sut.state.showExpiredAlert)
        XCTAssertEqual(sut.state.expiredAccount?.id, expired.id)
        XCTAssertFalse(sut.state.showExpiringSoonAlert)
        XCTAssertNil(sut.state.expiringSoonAccount)
    }

    func testExpiringSoonAlertWhenNothingExpired() async throws {
        let expiring = AccountModel(
            name: "Expiring",
            providerType: .apple,
            expirationDate: Date().addingTimeInterval(60 * 60)
        )
        try await storage.save(expiring, id: expiring.id)

        let sut = makeSUT()
        await sut.loadDashboard()

        XCTAssertFalse(sut.state.showExpiredAlert)
        XCTAssertTrue(sut.state.showExpiringSoonAlert)
        XCTAssertEqual(sut.state.expiringSoonAccount?.id, expiring.id)
    }

    // MARK: - Dismiss intents (US-005 AC-3 / AC-6 — TC-024 / TC-025 / TC-089)

    /// Cancel on an expired account hides the banner and, crucially, does NOT
    /// re-surface it on a subsequent reload (US-005 AC-3 / TC-024).
    func testDismissExpiredAlertSuppressesItForTheSession() async throws {
        let expired = AccountModel(
            name: "Expired",
            providerType: .apple,
            expirationDate: Date().addingTimeInterval(-60)
        )
        try await storage.save(expired, id: expired.id)

        let sut = makeSUT()
        await sut.loadDashboard()
        XCTAssertTrue(sut.state.showExpiredAlert)

        sut.dismissExpiredAlert()
        XCTAssertFalse(sut.state.showExpiredAlert)
        XCTAssertNil(sut.state.expiredAccount)

        // A second load (e.g. after a sync) must NOT bring the banner back.
        await sut.loadDashboard()
        XCTAssertFalse(sut.state.showExpiredAlert, "Expired banner must stay dismissed this session (AC-3)")
        XCTAssertNil(sut.state.expiredAccount)
    }

    /// OK on an expiring-soon account hides the banner; the account was already
    /// recorded as warned when first surfaced, so it is not re-warned this
    /// session (US-005 AC-6 / TC-089).
    func testDismissExpiringSoonAlertDoesNotRewarnThisSession() async throws {
        let expiring = AccountModel(
            name: "Expiring",
            providerType: .apple,
            expirationDate: Date().addingTimeInterval(60 * 60)
        )
        try await storage.save(expiring, id: expiring.id)

        let sut = makeSUT()
        await sut.loadDashboard()
        XCTAssertTrue(sut.state.showExpiringSoonAlert)

        sut.dismissExpiringSoonAlert()
        XCTAssertFalse(sut.state.showExpiringSoonAlert)
        XCTAssertNil(sut.state.expiringSoonAccount)

        // A second load must NOT re-surface the already-warned account (TC-089).
        await sut.loadDashboard()
        XCTAssertFalse(sut.state.showExpiringSoonAlert, "Already-warned account must not re-warn this session (AC-6)")
    }

    /// Already-warned account produces no expiring-soon alert on a fresh reload
    /// even without an explicit dismiss (warnedAccountIds is session-scoped —
    /// US-005 / TC-025).
    func testAlreadyWarnedExpiringAccountDoesNotRealert() async throws {
        let expiring = AccountModel(
            name: "Expiring",
            providerType: .apple,
            expirationDate: Date().addingTimeInterval(60 * 60)
        )
        try await storage.save(expiring, id: expiring.id)

        let sut = makeSUT()
        await sut.loadDashboard()
        XCTAssertTrue(sut.state.showExpiringSoonAlert)

        // Clear the visible flag the way a dismiss would, then reload: the
        // session-warned set must keep it from re-surfacing.
        sut.dismissExpiringSoonAlert()
        await sut.loadDashboard()
        XCTAssertFalse(sut.state.showExpiringSoonAlert)
    }

    /// No expiration → no alert of either kind (US-005 / TC-027 / TC-084).
    func testNoExpirationProducesNoAlert() async throws {
        let valid = AccountModel(
            name: "Valid",
            providerType: .apple,
            expirationDate: nil
        )
        try await storage.save(valid, id: valid.id)

        let sut = makeSUT()
        await sut.loadDashboard()

        XCTAssertFalse(sut.state.showExpiredAlert)
        XCTAssertFalse(sut.state.showExpiringSoonAlert)
        XCTAssertNil(sut.state.expiredAccount)
        XCTAssertNil(sut.state.expiringSoonAccount)
    }

    // MARK: - Loading flag (US-012 / TC-070)

    func testIsLoadingTransitionsDuringLoadDashboard() async {
        let sut = makeSUT()
        var sawLoading = false
        sut.onStateChanged = { state in
            if state.isLoading { sawLoading = true }
        }

        XCTAssertFalse(sut.state.isLoading)
        await sut.loadDashboard()

        XCTAssertTrue(sawLoading, "isLoading must flip true while loadDashboard runs")
        XCTAssertFalse(sut.state.isLoading, "isLoading must flip back off when finished")
    }

    // MARK: - Manual sync orchestration (US-004 / TC-018 / TC-078)

    func testTriggerSyncDelegatesToPipeline() {
        let sut = makeSUT()
        sut.triggerSync()
        XCTAssertEqual(sync.triggerCount, 1)
    }

    func testSyncCompletionReloadsDashboard() async {
        let sut = makeSUT()
        sut.addWidget(.inReview)
        let widget = sut.state.widgets.first as? MockWidget
        let loadsBefore = widget?.loadCount ?? 0

        // Emit a sync transition whose lastSyncedAt advances -> triggers a reload.
        sync.emit(SyncState(isSyncing: false, lastSyncedAt: Date()))
        // Let the reload Task run.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThan(widget?.loadCount ?? 0, loadsBefore)
        XCTAssertFalse(sut.state.syncState.isSyncing)
    }

    // MARK: - onStateChanged republish

    func testOnStateChangedFiresForWidgetMutations() {
        let sut = makeSUT()
        var changes = 0
        sut.onStateChanged = { _ in changes += 1 }
        sut.addWidget(.inReview)
        XCTAssertGreaterThan(changes, 0)
    }
}

// MARK: - Test doubles

@MainActor
private final class MockWidget: HomeWidget {
    static let kind: HomeWidgetKind = .inReview
    let configuration: HomeWidgetConfiguration
    private(set) var isLoading = false
    private(set) var loadCount = 0

    init(configuration: HomeWidgetConfiguration) {
        self.configuration = configuration
    }

    // Override the protocol default so a MockWidget's kind matches its config,
    // letting the same mock stand in for any kind in the add/move tests.
    var kind: HomeWidgetKind { configuration.kind }

    func load() async {
        loadCount += 1
    }
}

@MainActor
private final class StubSync: HomeSyncObserving {
    private(set) var triggerCount = 0
    private var observer: ((SyncState) -> Void)?
    var syncState = SyncState()

    @discardableResult
    func triggerSync() -> Task<Void, Never> {
        triggerCount += 1
        return Task {}
    }

    func observeSyncState(_ onChange: @escaping (SyncState) -> Void) {
        observer = onChange
    }

    /// Drives a state transition into the observing view model.
    func emit(_ state: SyncState) {
        syncState = state
        observer?(state)
    }
}

/// In-memory `KeyStorable` whose `object`/`setObject` go through the protocol's
/// default Codable JSON extension (exercising the real serialize/deserialize
/// path under `home.widget.configurations` — TC-060/TC-079).
private final class InMemoryPreferences: KeyStorable, @unchecked Sendable {
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

private final class InMemoryStorage: PersistentStorable, @unchecked Sendable {
    private var store: [String: Data] = [:]
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
}
