import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// The Play app list keeps its release-status refreshes under Google's quota
/// (`GooglePlayReleaseSummariesRefresher`): the first quota hit stops the run
/// and starts a persisted cooldown, a load asks nothing while it lasts, a pull
/// to refresh tries once and extends it, apps refreshed recently are skipped,
/// only the tracks known to hold a release are asked automatically, and other
/// errors behave as before.
@MainActor
final class GooglePlayAppListQuotaTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayAccountConnection!
    private var clock: TestClock!

    private let account = AccountModel(name: "Play Team", providerType: .googlePlay)
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayAccountConnection()
        clock = TestClock(start)
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        clock = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT() -> GooglePlayAppListViewModel {
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
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

    private func storedCooldown() async throws -> GooglePlayQuotaCooldown? {
        try await storage.fetch(GooglePlayQuotaCooldown.self, id: GooglePlayQuotaCooldown.storageId(accountId: account.id))
    }

    private func seedCooldown(until: Date) async throws {
        let cooldown = GooglePlayQuotaCooldown(accountId: account.id, until: until, recordedAt: start, message: "Quota exceeded")
        try await storage.save(cooldown, id: GooglePlayQuotaCooldown.storageId(accountId: account.id))
    }

    private func seedSummaries(_ packageName: String, _ summaries: [GooglePlayReleaseSummaryModel],
                               fetchedAt: Date? = nil, discoveredAt: Date? = nil) async throws {
        let entry = GooglePlayReleaseSummariesCache(accountId: account.id, packageName: packageName, summaries: summaries,
                                                    fetchedAt: fetchedAt, tracksDiscoveredAt: discoveredAt)
        try await storage.save(entry, id: entry.cacheKey)
    }

    private func cachedSummaries(_ packageName: String) async throws -> GooglePlayReleaseSummariesCache? {
        try await storage.fetch(
            GooglePlayReleaseSummariesCache.self,
            id: GooglePlayReleaseSummariesCache.cacheKey(accountId: account.id, packageName: packageName)
        )
    }

    nonisolated private static func quota(_ packageName: String, _ track: String, retryAfter: Int? = nil) -> StackError {
        FakeCoreError.playQuotaExceeded(retryAfterSeconds: retryAfter, request: "GET applications/\(packageName)/tracks/\(track)/releases")
    }

    // MARK: - Stop at the first hit

    func testTheFirstQuotaHitStopsTheRunAndKeepsTheCachedStatus() async throws {
        try await seedSummaries("com.a", [summary("production", "1.0 (10)", .inReview, "10")])
        connection.fetchAppsHandler = { (0..<6).map { app("com.\($0 == 0 ? "a" : "app\($0)")") } }
        connection.fetchReleaseSummariesHandler = { packageName, track in throw Self.quota(packageName, track) }
        let sut = makeSUT()

        await sut.load()

        XCTAssertLessThanOrEqual(connection.releaseSummaryRequests.count, GooglePlayAppListViewModel.maxConcurrentSummaryFetches,
                                 "No request starts after the first hit (24 were due)")
        XCTAssertEqual(sut.uiState.releaseStatus["com.a"]?.map(\.lifecycleState), [.inReview], "Cached status kept")
        let cached = try await cachedSummaries("com.a")
        XCTAssertEqual(cached?.summaries.map(\.lifecycleState), [.inReview])
        XCTAssertNil(sut.uiState.error, "Release status is best effort: no error, no alert")
    }

    func testFetchStopsSchedulingAfterTheFirstQuotaHit() async {
        let requests = ["com.a", "com.b", "com.c"].flatMap { packageName in
            GooglePlayAppListSync.standardTracks.map { (packageName: packageName, track: $0) }
        }
        let calls = LockedCounter()
        connection.fetchReleaseSummariesHandler = { packageName, track in
            if calls.increment() == 2 { throw Self.quota(packageName, track, retryAfter: 90) }
            return []
        }

        let result = await GooglePlayAppListSync.fetchReleaseSummaries(
            requests: requests, using: connection, maxConcurrent: 1, logTag: "Test"
        )

        XCTAssertEqual(connection.releaseSummaryRequests.count, 2)
        XCTAssertEqual(result.startedCount, 2)
        XCTAssertEqual(result.answeredCount, 1)
        XCTAssertEqual(result.quotaHit?.retryAfter, 90)
        XCTAssertTrue(result.summaries.isEmpty, "No package had every track answered")
        XCTAssertEqual(result.failed, ["com.a", "com.b", "com.c"])
    }

    // MARK: - Cooldown

    func testAQuotaHitPersistsACooldownOfAtLeastFifteenMinutesAndShowsTheFooter() async throws {
        connection.fetchAppsHandler = { [app("com.a")] }
        connection.fetchReleaseSummariesHandler = { packageName, track in throw Self.quota(packageName, track, retryAfter: 60) }
        let sut = makeSUT()

        await sut.load()

        let cooldown = try await storedCooldown()
        let expected = start.addingTimeInterval(GooglePlayReleaseSummariesRefresher.minimumCooldown)
        XCTAssertEqual(cooldown?.until, expected, "Retry-After 60 s is shorter than the minimum")
        XCTAssertEqual(cooldown?.recordedAt, start)
        XCTAssertEqual(sut.uiState.releaseStatusPausedUntil, expected)
        let time = expected.formatted(date: Calendar.current.isDateInToday(expected) ? .omitted : .abbreviated, time: .shortened)
        XCTAssertEqual(
            sut.uiState.releaseStatusPausedNote,
            String(localized: "Release status paused: Google Play API quota reached. Retrying after \(time).")
        )
    }

    func testALongerRetryAfterSetsTheCooldown() async throws {
        connection.fetchAppsHandler = { [app("com.a")] }
        connection.fetchReleaseSummariesHandler = { packageName, track in throw Self.quota(packageName, track, retryAfter: 1_800) }
        let sut = makeSUT()

        await sut.load()

        let cooldown = try await storedCooldown()
        XCTAssertEqual(cooldown?.until, start.addingTimeInterval(1_800))
    }

    func testALoadDuringTheCooldownAsksNothingAndShowsTheFooter() async throws {
        try await seedCooldown(until: start.addingTimeInterval(600))
        try await seedSummaries("com.a", [summary("production", "1.0 (10)", .published, "10")])
        connection.fetchAppsHandler = { [app("com.a"), app("com.b")] }
        let sut = makeSUT()

        await sut.load()

        XCTAssertTrue(connection.releaseSummaryRequests.isEmpty)
        XCTAssertEqual(connection.fetchAppsCallCount, 1, "The app list itself still syncs")
        XCTAssertEqual(sut.uiState.releaseStatus["com.a"]?.first?.versionName, "1.0")
        XCTAssertEqual(sut.uiState.releaseStatusPausedUntil, start.addingTimeInterval(600))
        XCTAssertNotNil(sut.uiState.releaseStatusPausedNote)
    }

    func testAnEndedCooldownIsDroppedAndTheStatusIsAskedAgain() async throws {
        try await seedCooldown(until: start.addingTimeInterval(-1))
        connection.fetchAppsHandler = { [app("com.a")] }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(connection.releaseSummaryRequests.count, GooglePlayAppListSync.standardTracks.count)
        let cooldown = try await storedCooldown()
        XCTAssertNil(cooldown)
        XCTAssertNil(sut.uiState.releaseStatusPausedNote)
    }

    func testPullToRefreshTriesOnceDuringTheCooldownAndAHitExtendsIt() async throws {
        let original = start.addingTimeInterval(300)
        try await seedCooldown(until: original)
        connection.fetchAppsHandler = { [app("com.a"), app("com.b")] }
        connection.fetchReleaseSummariesHandler = { packageName, track in throw Self.quota(packageName, track) }
        let sut = makeSUT()

        await sut.refresh()

        XCTAssertEqual(connection.releaseSummaryRequests.count, 1, "One probe request while cooling down")
        let extended = try await storedCooldown()
        XCTAssertEqual(extended?.until, start.addingTimeInterval(GooglePlayReleaseSummariesRefresher.minimumCooldown))
        XCTAssertGreaterThan(try XCTUnwrap(extended?.until), original)
        XCTAssertEqual(sut.uiState.releaseStatusPausedUntil, extended?.until)
    }

    func testPullToRefreshThatAnswersEndsTheCooldown() async throws {
        try await seedCooldown(until: start.addingTimeInterval(300))
        connection.fetchAppsHandler = { [app("com.a"), app("com.b")] }
        connection.fetchReleaseSummariesHandler = { _, track in [summary(track, "2.0 (20)", .published, "20")] }
        let sut = makeSUT()

        await sut.refresh()

        XCTAssertEqual(connection.releaseSummaryRequests.count, 2 * GooglePlayAppListSync.standardTracks.count)
        let cooldown = try await storedCooldown()
        XCTAssertNil(cooldown)
        XCTAssertNil(sut.uiState.releaseStatusPausedUntil)
        XCTAssertEqual(sut.uiState.releaseStatus["com.b"]?.count, 4)
    }

    func testANewHitNeverShortensALongerCooldown() async throws {
        let later = start.addingTimeInterval(3_600)
        try await seedCooldown(until: later)
        connection.fetchAppsHandler = { [app("com.a")] }
        connection.fetchReleaseSummariesHandler = { packageName, track in throw Self.quota(packageName, track) }
        let sut = makeSUT()

        await sut.refresh()

        let cooldown = try await storedCooldown()
        XCTAssertEqual(cooldown?.until, later)
    }

    func testTheFooterNeedsTheVersionRule() {
        var state = GooglePlayAppListUiState(account: account)
        state.releaseStatusPausedUntil = start
        XCTAssertNotNil(state.releaseStatusPausedNote)

        state.account = AccountModel(name: "Imported", providerType: .googlePlay,
                                     rules: AccountRules(apps: AccountPermission.allCases, review: [.view]), origin: .imported)
        XCTAssertNil(state.releaseStatusPausedNote)
    }

    // MARK: - Minimum interval

    func testALoadSkipsAppsRefreshedLessThanTenMinutesAgoButPullToRefreshDoesNot() async throws {
        connection.fetchAppsHandler = { [app("com.a")] }
        let sut = makeSUT()

        await sut.load()
        XCTAssertEqual(connection.releaseSummaryRequests.count, 4)

        clock.value = start.addingTimeInterval(5 * 60)
        await sut.load()
        XCTAssertEqual(connection.releaseSummaryRequests.count, 4, "Refreshed 5 minutes ago: skipped")

        await sut.refresh()
        XCTAssertEqual(connection.releaseSummaryRequests.count, 8, "Pull to refresh asks again")

        clock.value = start.addingTimeInterval(5 * 60 + GooglePlayReleaseSummariesRefresher.minimumAutomaticInterval)
        await sut.load()
        XCTAssertEqual(connection.releaseSummaryRequests.count, 8,
                       "Due again after the interval, but every track was found empty by the last discovery: nothing to ask")

        clock.value = start.addingTimeInterval(5 * 60 + GooglePlayReleaseSummariesRefresher.fullTrackDiscoveryInterval)
        await sut.load()
        XCTAssertEqual(connection.releaseSummaryRequests.count, 12, "The daily discovery asks every track again")
    }

    // MARK: - Fewer tracks

    func testALoadAsksOnlyTheTracksKnownToHoldARelease() async throws {
        try await seedSummaries("com.a", [summary("production", "1.0 (10)", .published, "10")],
                                fetchedAt: start.addingTimeInterval(-3_600), discoveredAt: start.addingTimeInterval(-3_600))
        let tracks = GooglePlayTracksCache(accountId: account.id, packageName: "com.a", tracks: [
            GooglePlayTrackModel(track: "production", releases: []),
            GooglePlayTrackModel(track: "internal", releases: [GooglePlayReleaseModel(name: "1.1", status: .draft, versionCodes: ["11"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)]),
            GooglePlayTrackModel(track: "beta", releases: [])
        ])
        try await storage.save(tracks, id: tracks.cacheKey)
        connection.fetchAppsHandler = { [app("com.a")] }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(connection.releaseSummaryRequests.map(\.track).sorted(), ["internal", "production"])
        let cached = try await cachedSummaries("com.a")
        XCTAssertEqual(cached?.tracksDiscoveredAt, start.addingTimeInterval(-3_600), "Not a full discovery")
    }

    func testEveryTrackIsAskedOnceADayAndWhenNeverDiscovered() async throws {
        try await seedSummaries("com.a", [summary("production", "1.0 (10)", .published, "10")],
                                fetchedAt: start.addingTimeInterval(-3_600),
                                discoveredAt: start.addingTimeInterval(-GooglePlayReleaseSummariesRefresher.fullTrackDiscoveryInterval))
        try await seedSummaries("com.b", [], fetchedAt: start.addingTimeInterval(-3_600), discoveredAt: nil)
        try await seedSummaries("com.c", [], fetchedAt: start.addingTimeInterval(-3_600), discoveredAt: start.addingTimeInterval(-60))
        connection.fetchAppsHandler = { [app("com.a"), app("com.b"), app("com.c")] }
        let sut = makeSUT()

        await sut.load()

        let asked = Dictionary(grouping: connection.releaseSummaryRequests, by: \.packageName).mapValues { Set($0.map(\.track)) }
        XCTAssertEqual(asked["com.a"], Set(GooglePlayAppListSync.standardTracks), "Discovery older than a day")
        XCTAssertEqual(asked["com.b"], Set(GooglePlayAppListSync.standardTracks), "Never discovered")
        XCTAssertNil(asked["com.c"], "Discovered a minute ago with every track empty: known empty until the next discovery")
        let cached = try await cachedSummaries("com.a")
        XCTAssertEqual(cached?.tracksDiscoveredAt, start)
    }

    func testATracksCacheOlderThanTheLastDiscoveryDoesNotAddTracks() async throws {
        let discovery = start.addingTimeInterval(-3_600)
        try await seedSummaries("com.a", [summary("production", "1.0 (10)", .published, "10")],
                                fetchedAt: discovery, discoveredAt: discovery)
        let stale = GooglePlayTracksCache(accountId: account.id, packageName: "com.a", tracks: [
            GooglePlayTrackModel(track: "beta", releases: [GooglePlayReleaseModel(name: "0.9", status: .completed, versionCodes: ["9"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)])
        ], fetchedAt: discovery.addingTimeInterval(-60))
        try await storage.save(stale, id: stale.cacheKey)
        connection.fetchAppsHandler = { [app("com.a")] }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(connection.releaseSummaryRequests.map(\.track), ["production"],
                       "Beta was asked (and answered empty) by the later discovery")
    }

    // MARK: - Other errors

    func testANonQuotaErrorNeitherStopsTheRunNorStartsACooldown() async throws {
        connection.fetchAppsHandler = { [app("com.a"), app("com.b")] }
        connection.fetchReleaseSummariesHandler = { packageName, track in
            if packageName == "com.a", track == "production" { throw StackError.Http(status: 500, message: "boom") }
            return [summary(track, "2.0 (20)", .published, "20")]
        }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(connection.releaseSummaryRequests.count, 8, "Every request still runs")
        let cooldown = try await storedCooldown()
        XCTAssertNil(cooldown)
        XCTAssertNil(sut.uiState.releaseStatusPausedNote)
        XCTAssertEqual(sut.uiState.releaseStatus["com.b"]?.count, 4)
        XCTAssertNil(sut.uiState.releaseStatus["com.a"])
    }

    // MARK: - Parsing

    func testRetryAfterAndGooglesMessageAreReadFromTheCoresQuotaMessage() {
        let withRetry = "Listing releases quota exceeded. [PERMISSION_DENIED]; this is a Google Play API quota/rate limit, "
            + "not a permission problem — wait and retry later (Retry-After: 60 s) (HTTP 403 on GET applications/com.a/tracks/beta/releases)"
        XCTAssertEqual(GooglePlayQuota.retryAfter(in: withRetry), 60)
        XCTAssertEqual(GooglePlayQuota.googleMessage(in: withRetry), "Listing releases quota exceeded. [PERMISSION_DENIED]")

        let withoutRetry = "Quota exceeded [RESOURCE_EXHAUSTED]; this is a Google Play API quota/rate limit, not a permission problem "
            + "— wait and retry later (HTTP 429 on GET v1beta1/apps:search)"
        XCTAssertNil(GooglePlayQuota.retryAfter(in: withoutRetry))
        XCTAssertEqual(GooglePlayQuota.googleMessage(in: withoutRetry), "Quota exceeded [RESOURCE_EXHAUSTED]")

        XCTAssertEqual(GooglePlayQuota.googleMessage(in: "  RESOURCE_EXHAUSTED \n"), "RESOURCE_EXHAUSTED")
        XCTAssertTrue(GooglePlayQuota.isQuotaExceeded(StackError.Http(status: 429, message: "")))
        XCTAssertFalse(GooglePlayQuota.isQuotaExceeded(StackError.Http(status: 403, message: "quota")))
        XCTAssertFalse(GooglePlayQuota.isQuotaExceeded(StackError.Auth(message: "Listing releases quota exceeded.")))
        XCTAssertNil(GooglePlayQuota.hit(from: URLError(.timedOut)))
    }
}

// MARK: - Helpers

private func app(_ packageName: String, name: String? = nil) -> StackProtocols.AppInfo {
    StackProtocols.AppInfo(id: packageName, name: name ?? packageName, bundleId: packageName, platform: "ANDROID")
}

private func summary(_ track: String, _ name: String?, _ state: GooglePlayReleaseLifecycleState, _ code: String) -> GooglePlayReleaseSummaryModel {
    GooglePlayReleaseSummaryModel(track: track, name: name, lifecycleState: state, versionCodes: [code])
}

/// A settable clock shared with `@Sendable` closures.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Date
    init(_ value: Date) { _value = value }
    var value: Date {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// A counter shared with `@Sendable` mock handlers.
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    /// Increments and returns the new count.
    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
