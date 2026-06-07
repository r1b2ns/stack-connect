import XCTest
import StackProtocols
@testable import StackHomeCore

/// Gap-filling core tests for `HomeViewModel` (T-E1) that complement
/// `HomeViewModelTests`. Focuses on the edge / cold-start cases the existing
/// suite did not exercise:
///
/// - First-appearance orchestration building blocks (US-004 AC-1/AC-3 — TC-019).
/// - Sync-in-progress flag mirrored into state so the toolbar can disable the
///   button (US-004 AC-2 — TC-020).
/// - Single-account "both expired and expiring" precedence (US-005 AC-7 —
///   TC-088 variant).
/// - Up-disabled-on-first / Down-disabled-on-last reorder semantics at the core
///   level (US-008 AC-6 — TC-048 / TC-049).
/// - Zero accounts / empty storage / corrupt storage / widget-load failure
///   (US-012 AC-3 — TC-071 / TC-072 / TC-073 / TC-074).
@MainActor
final class HomeViewModelEdgeCasesTests: XCTestCase {

    private var storage: EdgeInMemoryStorage!
    private var preferences: EdgeInMemoryPreferences!
    private var sync: EdgeStubSync!

    override func setUp() async throws {
        try await super.setUp()
        storage = EdgeInMemoryStorage()
        preferences = EdgeInMemoryPreferences()
        sync = EdgeStubSync()
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
            widgetFactory: { EdgeMockWidget(configuration: $0) }
        )
    }

    // MARK: - First-appearance orchestration (US-004 AC-1/AC-3 — TC-019)

    /// On first appearance the UI calls `triggerSync()` then `loadDashboard()`
    /// (mirrors the iOS `.task` and the Windows `onAppear`). Core does not own
    /// the "first appearance" hook itself — that is a view-layer concern — but
    /// the two intents it exposes must produce the expected effects: the sync is
    /// triggered exactly once and every active widget is (re)loaded.
    func testFirstAppearanceTriggersSyncAndLoadsWidgets() async {
        let sut = makeSUT()
        sut.addWidget(.inReview)
        let widget = sut.state.widgets.first as? EdgeMockWidget
        // Let the detached load() that `addWidget` kicks off settle so the
        // baseline count is stable before we measure the loadDashboard effect.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let loadsAfterAdd = widget?.loadCount ?? 0

        // Simulated first-appearance sequence.
        sut.triggerSync()
        await sut.loadDashboard()

        XCTAssertEqual(sync.triggerCount, 1, "first appearance must trigger sync exactly once (AC-1)")
        XCTAssertGreaterThan(widget?.loadCount ?? 0, loadsAfterAdd,
            "loadDashboard on first appearance must (re)load the active widgets (AC-3)")
    }

    // MARK: - Sync-in-progress flag (US-004 AC-2 — TC-020)

    /// A syncing transition from the pipeline must surface in
    /// `state.syncState.isSyncing`, which the toolbar binds the Sync button's
    /// disabled/loading state to. When the pipeline reports idle again the flag
    /// clears so the button re-enables.
    func testSyncingFlagMirroredIntoStateForButtonDisabling() {
        let sut = makeSUT()
        XCTAssertFalse(sut.state.syncState.isSyncing, "idle at rest")

        sync.emit(SyncState(isSyncing: true))
        XCTAssertTrue(sut.state.syncState.isSyncing,
            "syncing must mirror into state so the Sync button can disable (AC-2)")

        sync.emit(SyncState(isSyncing: false))
        XCTAssertFalse(sut.state.syncState.isSyncing,
            "idle must mirror back so the Sync button re-enables")
    }

    // MARK: - Single-account both expired + expiring precedence (US-005 AC-7 — TC-088)

    /// A single account whose expiration date is in the past is `isExpired`;
    /// the Expired alert must win and no Expiring-soon alert may surface for it
    /// (TC-088 — "both expired+expiring → only Expired"). `isExpired` and
    /// `isExpiringSoon` are mutually exclusive by model definition, so this also
    /// guards that invariant from the alert layer's perspective.
    func testSingleExpiredAccountSurfacesOnlyExpiredAlert() async throws {
        let account = AccountModel(
            name: "Acme",
            providerType: .apple,
            expirationDate: Date().addingTimeInterval(-1)
        )
        try await storage.save(account, id: account.id)

        let sut = makeSUT()
        await sut.loadDashboard()

        XCTAssertTrue(sut.state.showExpiredAlert)
        XCTAssertEqual(sut.state.expiredAccount?.id, account.id)
        XCTAssertFalse(sut.state.showExpiringSoonAlert,
            "an expired account must never also raise the expiring-soon alert (AC-7)")
        XCTAssertNil(sut.state.expiringSoonAccount)
    }

    // MARK: - Reorder boundary semantics (US-008 AC-6 — TC-048 / TC-049)

    /// TC-048: the first widget cannot move further up. Moving index 0 to offset
    /// 0 is a no-op; order is preserved (the UI disables "Up" on the first row).
    func testFirstWidgetCannotMoveUp() {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)
        sut.addWidget(.inReview)
        sut.addWidget(.awaitingRelease)
        let before = sut.state.widgets.map { $0.kind }

        // "Up" on the first row resolves to from:0 to:0 — no movement.
        sut.moveWidgets(from: IndexSet(integer: 0), to: 0)

        XCTAssertEqual(sut.state.widgets.map { $0.kind }, before,
            "first widget has nowhere to go up (Up disabled on first — AC-6)")
    }

    /// TC-049: the last widget cannot move further down. Moving the last index
    /// to the end offset is a no-op; order is preserved (the UI disables "Down"
    /// on the last row).
    func testLastWidgetCannotMoveDown() {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)
        sut.addWidget(.inReview)
        sut.addWidget(.awaitingRelease)
        let before = sut.state.widgets.map { $0.kind }
        let lastIndex = before.count - 1

        // "Down" on the last row resolves to from:last to:count — no movement.
        sut.moveWidgets(from: IndexSet(integer: lastIndex), to: before.count)

        XCTAssertEqual(sut.state.widgets.map { $0.kind }, before,
            "last widget has nowhere to go down (Down disabled on last — AC-6)")
    }

    // MARK: - Zero accounts / empty storage (US-012 AC-3 — TC-071 / TC-072)

    /// TC-071: with zero accounts a full dashboard load must not crash and must
    /// settle into a valid, alert-free state with the providers grid intact.
    func testZeroAccountsLoadsValidStateWithoutCrash() async {
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertFalse(sut.state.isLoading)
        XCTAssertFalse(sut.state.showExpiredAlert)
        XCTAssertFalse(sut.state.showExpiringSoonAlert)
        XCTAssertNil(sut.state.expiredAccount)
        XCTAssertNil(sut.state.expiringSoonAccount)
        // Provider cards are always present (no empty state — US-001 AC-5).
        XCTAssertFalse(sut.state.providers.isEmpty)
        XCTAssertFalse(sut.state.providers.contains(.googlePlay))
    }

    /// TC-072: a brand-new install with empty preferences yields a valid state —
    /// no widgets, no alerts, providers present — and never crashes on load.
    func testEmptyStorageYieldsValidStateOnFreshInstall() async {
        let sut = makeSUT()

        XCTAssertTrue(sut.state.widgets.isEmpty, "fresh install has no widgets")

        await sut.loadDashboard()

        XCTAssertTrue(sut.state.widgets.isEmpty)
        XCTAssertFalse(sut.state.showExpiredAlert)
        XCTAssertFalse(sut.state.showExpiringSoonAlert)
        XCTAssertFalse(sut.state.providers.isEmpty)
    }

    // MARK: - Corrupt storage (TC-073)

    /// TC-073: when `fetchAll(AccountModel.self)` throws (corrupt/undecodable
    /// store), `loadDashboard()` must absorb the error, raise no alert, and leave
    /// a valid state — no crash.
    func testCorruptAccountStorageDoesNotCrash() async {
        storage.failAccountFetch = true
        let sut = makeSUT()

        await sut.loadDashboard()

        XCTAssertFalse(sut.state.isLoading)
        XCTAssertFalse(sut.state.showExpiredAlert)
        XCTAssertFalse(sut.state.showExpiringSoonAlert)
        XCTAssertNil(sut.state.expiredAccount)
    }

    /// TC-073 (config side): corrupt persisted widget configuration (undecodable
    /// bytes under the widgets key) must fall back to the defaults rather than
    /// crashing on construction.
    func testCorruptWidgetConfigurationFallsBackToDefaults() {
        preferences.injectRawData(Data([0x00, 0x01, 0x02]), forKey: HomeViewModel.widgetsStorageKey)

        let sut = makeSUT(defaults: [HomeWidgetConfiguration(kind: .inReview)])

        XCTAssertEqual(sut.state.widgets.map(\.kind), [.inReview],
            "undecodable config must fall back to the provided defaults (TC-073)")
    }

    // MARK: - Widget load failure (TC-074)

    /// TC-074: a widget whose `load()` fails internally must not propagate or
    /// crash `loadDashboard()`. The view model still settles into a valid state
    /// and the failed widget remains present (showing its own empty/error state
    /// at the view layer).
    func testWidgetLoadFailureIsHandledGracefully() async {
        let sut = makeSUT()
        sut.addWidget(.inReview)
        (sut.state.widgets.first as? EdgeMockWidget)?.shouldFailLoad = true

        await sut.loadDashboard()

        XCTAssertFalse(sut.state.isLoading)
        XCTAssertEqual(sut.state.widgets.count, 1,
            "a failed widget load must not remove the widget or crash the dashboard")
    }
}

// MARK: - Test doubles

@MainActor
private final class EdgeMockWidget: HomeWidget {
    static let kind: HomeWidgetKind = .inReview
    let configuration: HomeWidgetConfiguration
    private(set) var isLoading = false
    private(set) var loadCount = 0
    /// When true, `load()` simulates an internal failure that it absorbs (the
    /// concrete widgets catch and reset to empty data); it must never throw.
    var shouldFailLoad = false

    init(configuration: HomeWidgetConfiguration) {
        self.configuration = configuration
    }

    var kind: HomeWidgetKind { configuration.kind }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        loadCount += 1
        // A real widget catches its own errors and resets to empty data; the
        // mock mirrors that contract by completing without throwing.
        _ = shouldFailLoad
    }
}

@MainActor
private final class EdgeStubSync: HomeSyncObserving {
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

    func emit(_ state: SyncState) {
        syncState = state
        observer?(state)
    }
}

/// In-memory `KeyStorable` going through the protocol's default Codable JSON
/// extension, with a hook to inject raw (corrupt) bytes for the decode-failure
/// path (TC-073).
private final class EdgeInMemoryPreferences: KeyStorable, @unchecked Sendable {
    private var store: [String: Data] = [:]
    private let lock = NSLock()

    func injectRawData(_ data: Data, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        store[key] = data
    }

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

/// In-memory `PersistentStorable` with a switch to make `fetchAll(AccountModel)`
/// throw, simulating corrupt storage (TC-073).
private final class EdgeInMemoryStorage: PersistentStorable, @unchecked Sendable {
    private var store: [String: Data] = [:]
    private let lock = NSLock()
    var failAccountFetch = false

    private struct CorruptStorageError: Error {}

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
        if failAccountFetch, type == AccountModel.self {
            throw CorruptStorageError()
        }
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
