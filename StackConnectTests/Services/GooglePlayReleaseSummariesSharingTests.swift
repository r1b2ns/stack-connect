import XCTest
import StackProtocols
@testable import StackConnect

/// The Home / background sync leg (`GooglePlayAccountSync`) and the Play app
/// list (`GooglePlayAppListViewModel`) share one source of truth for the
/// release status of an account: the same cache, saved by the shared
/// `GooglePlayReleaseSummariesRefresher` run, and one run per account at a
/// time (`GooglePlayReleaseSummariesRuns`).
///
/// Device report this reproduces: the Home sync asked production / beta /
/// alpha / internal of every app, then opening the Play app list ~25 s later
/// asked all four tracks of every app again; beta and alpha answered 204 No
/// Content (no release).
@MainActor
final class GooglePlayReleaseSummariesSharingTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayAccountConnection!
    private var clock: SharingBox<Date>!

    private let account = AccountModel(name: "Play Team", providerType: .googlePlay)
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let packages = ["com.a", "com.b", "com.c"]

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayAccountConnection()
        clock = SharingBox(start)
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
        let packages = self.packages
        connection.fetchAppsHandler = { packages.map { sharingApp($0) } }
        // Production and internal hold a release; beta and alpha are empty.
        connection.fetchReleaseSummariesHandler = { _, track in
            switch track {
            case "production": return [sharingSummary(track, .published, "20")]
            case "internal": return [sharingSummary(track, .inReview, "21")]
            default: return []
            }
        }
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        clock = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func sync() async -> SyncChange {
        let clock = self.clock!
        return await GooglePlayAccountSync(
            account: account, connection: connection, storage: storage, mode: .full, now: { clock.value }
        ).run()
    }

    private func makeList() -> GooglePlayAppListViewModel {
        let clock = self.clock!
        return GooglePlayAppListViewModel(
            account: account,
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.appListFactory,
            accessCheckerFactory: { _ in MockGooglePlayAppAccessChecker() },
            connectivity: MockConnectivityProviding(online: true),
            now: { clock.value }
        )
    }

    private var requestCount: Int { connection.releaseSummaryRequests.count }

    /// Tracks asked per package since request number `from`.
    private func askedTracks(from: Int = 0) -> [String: [String]] {
        let requests = connection.releaseSummaryRequests.dropFirst(from)
        return Dictionary(grouping: requests, by: \.packageName).mapValues { $0.map(\.track).sorted() }
    }

    private func waitUntil(_ what: String, _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Timed out waiting for \(what)")
    }

    // MARK: - Home sync, then the app list

    func testAListLoadRightAfterTheHomeSyncAsksNothing() async throws {
        _ = await sync()
        XCTAssertEqual(requestCount, packages.count * GooglePlayAppListSync.standardTracks.count,
                       "First run: every standard track of every app")

        clock.value = start.addingTimeInterval(25)
        let list = makeList()
        await list.load()

        XCTAssertEqual(requestCount, packages.count * GooglePlayAppListSync.standardTracks.count,
                       "Refreshed by the sync 25 s ago: the list asks nothing")
        for packageName in packages {
            XCTAssertEqual(list.uiState.releaseStatus[packageName]?.map(\.lifecycleState), [.published, .inReview],
                           "The list shows what the sync cached")
        }
    }

    func testEmptyTracksAreCachedSoTheAppIsNotAskedAgainWithinTheInterval() async throws {
        _ = await sync()

        let cached = try await storage.fetch(
            GooglePlayReleaseSummariesCache.self,
            id: GooglePlayReleaseSummariesCache.cacheKey(accountId: account.id, packageName: "com.a")
        )
        XCTAssertEqual(cached?.fetchedAt, start)
        XCTAssertEqual(cached?.tracksDiscoveredAt, start)
        XCTAssertEqual(Set(cached?.summaries.map(\.track) ?? []), ["production", "internal"])
    }

    // MARK: - Concurrent callers

    func testASyncAndAListLoadRunningTogetherAskEachTrackOnce() async throws {
        let gate = SharingGate()
        let handler = connection.fetchReleaseSummariesHandler
        connection.fetchReleaseSummariesHandler = { packageName, track in
            await gate.wait()
            return try await handler(packageName, track)
        }
        let runs = GooglePlayReleaseSummariesRuns.shared
        let accountId = account.id

        let syncTask = Task { await self.sync() }
        try await waitUntil("the sync's run") { await runs.isRunning(accountId: accountId) }

        let list = makeList()
        let listTask = Task { await list.load() }
        try await waitUntil("the list to join the run") { await runs.waitingCallers(accountId: accountId) == 1 }

        gate.open()
        _ = await syncTask.value
        await listTask.value

        let asked = connection.releaseSummaryRequests.map { "\($0.packageName)/\($0.track)" }
        XCTAssertEqual(asked.count, Set(asked).count, "No app/track asked twice")
        XCTAssertEqual(asked.count, packages.count * GooglePlayAppListSync.standardTracks.count)
        XCTAssertEqual(list.uiState.releaseStatus["com.b"]?.map(\.lifecycleState), [.published, .inReview],
                       "The list shows the shared run's result")
        let stillRunning = await runs.isRunning(accountId: accountId)
        XCTAssertFalse(stillRunning)
    }

    func testACallerJoiningARunInFlightSharesItsOutcome() async throws {
        let gate = SharingGate()
        connection.fetchReleaseSummariesHandler = { _, track in
            await gate.wait()
            return track == "production" ? [sharingSummary(track, .published, "20")] : []
        }
        let runs = GooglePlayReleaseSummariesRuns()
        // Two stores: the second caller would ask everything again if it ran
        // on its own (nothing cached there), so no request proves it shared.
        let first = refresher(storage: storage, runs: runs)
        let second = refresher(storage: MockPersistentStorable(), runs: runs)
        let accountId = account.id

        let firstTask = Task.detached { await first.refresh(packages: ["com.a", "com.b"], trigger: .automatic) }
        try await waitUntil("the first run") { await runs.isRunning(accountId: accountId) }
        let secondTask = Task.detached { await second.refresh(packages: ["com.b"], trigger: .automatic) }
        try await waitUntil("the second caller to join") { await runs.waitingCallers(accountId: accountId) == 1 }
        gate.open()

        let firstOutcome = await firstTask.value
        let secondOutcome = await secondTask.value

        XCTAssertEqual(requestCount, 2 * GooglePlayAppListSync.standardTracks.count)
        XCTAssertFalse(firstOutcome.sharedInFlightRun)
        XCTAssertEqual(firstOutcome.requestCount, 8)
        XCTAssertTrue(secondOutcome.sharedInFlightRun)
        XCTAssertEqual(secondOutcome.requestCount, 0)
        XCTAssertEqual(Array(secondOutcome.entries.keys), ["com.b"], "Only the apps it asked for")
    }

    func testAPullToRefreshDuringAnAutomaticRunWaitsThenAsksAgain() async throws {
        let gate = SharingGate()
        let handler = connection.fetchReleaseSummariesHandler
        connection.fetchReleaseSummariesHandler = { packageName, track in
            await gate.wait()
            return try await handler(packageName, track)
        }
        let runs = GooglePlayReleaseSummariesRuns.shared
        let accountId = account.id

        let syncTask = Task { await self.sync() }
        try await waitUntil("the sync's run") { await runs.isRunning(accountId: accountId) }
        let list = makeList()
        let refreshTask = Task { await list.refresh() }
        try await waitUntil("the pull to refresh to wait") { await runs.waitingCallers(accountId: accountId) == 1 }
        XCTAssertEqual(requestCount, GooglePlayReleaseSummariesRefresher.maxConcurrentFetches,
                       "Nothing asked by the pull to refresh while the sync runs")

        gate.open()
        _ = await syncTask.value
        await refreshTask.value

        let perRun = packages.count * GooglePlayAppListSync.standardTracks.count
        XCTAssertEqual(requestCount, 2 * perRun, "The pull to refresh still forces every track, after the sync's run")
    }

    // MARK: - Tracks asked

    func testAfterDiscoveryOnlyTheTracksWithAReleaseAreAskedAutomatically() async throws {
        _ = await sync()
        let afterDiscovery = requestCount

        clock.value = start.addingTimeInterval(GooglePlayReleaseSummariesRefresher.minimumAutomaticInterval + 60)
        let list = makeList()
        await list.load()

        XCTAssertEqual(askedTracks(from: afterDiscovery), [
            "com.a": ["internal", "production"],
            "com.b": ["internal", "production"],
            "com.c": ["internal", "production"]
        ], "Beta and alpha answered empty at the discovery: not asked")

        let afterList = requestCount
        clock.value = start.addingTimeInterval(2 * (GooglePlayReleaseSummariesRefresher.minimumAutomaticInterval + 60))
        _ = await sync()
        XCTAssertEqual(askedTracks(from: afterList)["com.a"], ["internal", "production"], "Same on the Home sync")
    }

    func testTheDailyDiscoveryAsksEveryTrack() async throws {
        _ = await sync()
        let afterDiscovery = requestCount

        clock.value = start.addingTimeInterval(GooglePlayReleaseSummariesRefresher.fullTrackDiscoveryInterval)
        _ = await sync()

        let standard = GooglePlayAppListSync.standardTracks.sorted()
        XCTAssertEqual(askedTracks(from: afterDiscovery), ["com.a": standard, "com.b": standard, "com.c": standard])
    }

    func testPullToRefreshRightAfterTheSyncStillAsksEveryTrack() async throws {
        _ = await sync()
        let afterSync = requestCount

        clock.value = start.addingTimeInterval(30)
        let list = makeList()
        await list.refresh()

        let standard = GooglePlayAppListSync.standardTracks.sorted()
        XCTAssertEqual(askedTracks(from: afterSync), ["com.a": standard, "com.b": standard, "com.c": standard])
    }

    func testTheSyncReportsAChangeTheListFetched() async throws {
        let state = SharingBox<GooglePlayReleaseLifecycleState>(.inReview)
        connection.fetchReleaseSummariesHandler = { _, track in
            track == "production" ? [sharingSummary(track, state.value, "20")] : []
        }
        _ = await sync()

        // The status changes; a list run on the same account refreshes it
        // while the sync leg joins that run: the sync still reports it.
        state.value = .published
        clock.value = start.addingTimeInterval(GooglePlayReleaseSummariesRefresher.minimumAutomaticInterval + 60)
        let gate = SharingGate()
        let handler = connection.fetchReleaseSummariesHandler
        connection.fetchReleaseSummariesHandler = { packageName, track in
            await gate.wait()
            return try await handler(packageName, track)
        }
        let runs = GooglePlayReleaseSummariesRuns.shared
        let accountId = account.id
        let list = makeList()
        let listTask = Task { await list.load() }
        try await waitUntil("the list's run") { await runs.isRunning(accountId: accountId) }
        let syncTask = Task { await self.sync() }
        try await waitUntil("the sync to join") { await runs.waitingCallers(accountId: accountId) == 1 }
        gate.open()
        await listTask.value
        let change = await syncTask.value

        XCTAssertEqual(change.statusChanges.count, packages.count)
        XCTAssertEqual(Set(change.statusChanges.map(\.appId)), Set(packages))
    }

    // MARK: - Factory

    private func refresher(storage: PersistentStorable, runs: GooglePlayReleaseSummariesRuns) -> GooglePlayReleaseSummariesRefresher {
        let clock = self.clock!
        return GooglePlayReleaseSummariesRefresher(
            accountId: account.id,
            storage: storage,
            fetcher: connection,
            logTag: "Test",
            now: { clock.value },
            runs: runs
        )
    }
}

// MARK: - Helpers

private func sharingApp(_ packageName: String) -> StackProtocols.AppInfo {
    StackProtocols.AppInfo(id: packageName, name: packageName, bundleId: packageName, platform: "ANDROID")
}

private func sharingSummary(_ track: String, _ state: GooglePlayReleaseLifecycleState, _ code: String) -> GooglePlayReleaseSummaryModel {
    GooglePlayReleaseSummaryModel(track: track, name: "\(code) (\(code))", lifecycleState: state, versionCodes: [code])
}

/// A settable value (the clock, a lifecycle state) shared with `@Sendable` closures.
private final class SharingBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Holds every caller of `wait()` until `open()`.
private final class SharingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}
