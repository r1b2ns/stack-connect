import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// Release status on the Google Play app list (plan R1, T3): edit-free release
/// summaries fetched after the app sync — bounded, scope-checked, gated by the
/// `version` rule, never offline — persisted per app, and a failure keeps the
/// cached status. Also the search field.
@MainActor
final class GooglePlayAppListReleaseStatusTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayAccountConnection!

    private let account = AccountModel(name: "Play Team", providerType: .googlePlay)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayAccountConnection()
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT(account: AccountModel? = nil, online: Bool = true) -> GooglePlayAppListViewModel {
        let account = account ?? self.account
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
        return GooglePlayAppListViewModel(
            account: account,
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.appListFactory,
            accessCheckerFactory: { _ in MockGooglePlayAppAccessChecker() },
            connectivity: MockConnectivityProviding(online: online)
        )
    }

    private func cachedSummaries(_ packageName: String, accountId: String? = nil) async throws -> GooglePlayReleaseSummariesCache? {
        try await storage.fetch(
            GooglePlayReleaseSummariesCache.self,
            id: GooglePlayReleaseSummariesCache.cacheKey(accountId: accountId ?? account.id, packageName: packageName)
        )
    }

    private func seedSummaries(_ packageName: String, _ summaries: [GooglePlayReleaseSummaryModel]) async throws {
        let entry = GooglePlayReleaseSummariesCache(accountId: account.id, packageName: packageName, summaries: summaries, fetchedAt: nil)
        try await storage.save(entry, id: entry.cacheKey)
    }

    private func summariesSaveCount() async -> Int {
        await storage.saveCallCount[String(describing: GooglePlayReleaseSummariesCache.self)] ?? 0
    }

    // MARK: - Fetch and status lines

    func testLoadFetchesTheStandardTracksOfEveryAppAndShowsOneLinePerTrack() async throws {
        connection.fetchAppsHandler = { [app("com.a", name: "A")] }
        connection.fetchReleaseSummariesHandler = { _, track in
            switch track {
            case "production": return [summary("production", "4.2.0 (420)", .inReview, "420"), summary("production", "4.1.0 (410)", .published, "410")]
            case "internal":   return [summary("internal", nil, .draft, "430")]
            default:           return []
            }
        }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(Set(connection.releaseSummaryRequests.map(\.track)), Set(GooglePlayAppListViewModel.standardTracks))
        XCTAssertEqual(connection.editBasedReadCount, 0, "Release status never opens a Play edit")
        let lines = try XCTUnwrap(sut.uiState.releaseStatus["com.a"])
        XCTAssertEqual(lines, [
            GooglePlayTrackStatusLine(track: "production", lifecycleState: .inReview, versionName: "4.2.0"),
            GooglePlayTrackStatusLine(track: "internal", lifecycleState: .draft, versionName: nil)
        ])
        XCTAssertEqual(lines.first?.text, "\(String(localized: "Production")) · \(String(localized: "In review"))")
        let cached = try await cachedSummaries("com.a")
        XCTAssertEqual(cached?.summaries.count, 3)
        XCTAssertNotNil(cached?.fetchedAt)
    }

    func testEachAppIsPersistedOnceAfterAllItsTracksAnswered() async {
        connection.fetchAppsHandler = { [app("com.a"), app("com.b")] }
        connection.fetchReleaseSummariesHandler = { _, track in [summary(track, "1", .published, "1")] }
        let sut = makeSUT()

        await sut.load()

        let saves = await summariesSaveCount()
        XCTAssertEqual(saves, 2)
    }

    func testCustomTracksKnownFromTheTracksCacheAreAskedToo() async throws {
        let tracks = GooglePlayTracksCache(accountId: account.id, packageName: "com.a", tracks: [
            GooglePlayTrackModel(track: "production", releases: []),
            GooglePlayTrackModel(track: "city-partners", releases: [])
        ])
        try await storage.save(tracks, id: tracks.cacheKey)
        connection.fetchAppsHandler = { [app("com.a")] }
        let sut = makeSUT()

        await sut.load()

        // The first requests run concurrently, so they may start in any order.
        let asked = connection.releaseSummaryRequests.map(\.track)
        XCTAssertEqual(asked.sorted(), (GooglePlayAppListViewModel.standardTracks + ["city-partners"]).sorted())
        XCTAssertEqual(asked.last, "city-partners", "Custom tracks are asked after the standard ones")
    }

    func testSummaryFetchesAreBoundedInFlight() async {
        let packages = (0..<6).map { "com.app\($0)" }
        connection.fetchAppsHandler = { packages.map { app($0) } }
        let gate = AsyncGate()
        connection.fetchReleaseSummariesHandler = { _, _ in
            await gate.wait()
            return []
        }
        let sut = makeSUT()
        let limit = GooglePlayAppListViewModel.maxConcurrentSummaryFetches

        let loading = Task { await sut.load() }
        await gate.waitForArrivals(limit + 1)
        let startedWhileBlocked = await gate.arrivals
        await gate.open()
        await loading.value

        XCTAssertEqual(startedWhileBlocked, limit)
        XCTAssertLessThanOrEqual(connection.maxSummaryFetchesInFlight, limit)
        XCTAssertEqual(connection.releaseSummaryRequests.count, packages.count * GooglePlayAppListViewModel.standardTracks.count)
    }

    // MARK: - Guards

    func testAppsOutsideTheScopeAreNeverAsked() async {
        let scoped = AccountModel(name: "Imported", providerType: .googlePlay, rules: .allPermissions,
                                  origin: .imported, appsBundles: ["com.shared"])
        connection.fetchAppsHandler = { [app("com.shared"), app("com.hidden")] }
        let sut = makeSUT(account: scoped)

        await sut.load()

        XCTAssertEqual(Set(connection.releaseSummaryRequests.map(\.packageName)), ["com.shared"])
    }

    func testNothingIsFetchedOffline() async throws {
        try await storage.save([GooglePlayAppItem(id: "com.a", packageName: "com.a", title: "A", isManuallyAdded: false)],
                               id: GooglePlayAppItem.cacheKey(accountId: account.id))
        try await seedSummaries("com.a", [summary("production", "1.0 (10)", .published, "10")])
        connection.fetchAppsHandler = { throw OfflineError.noConnection }
        let sut = makeSUT(online: false)

        await sut.load()

        XCTAssertTrue(connection.releaseSummaryRequests.isEmpty)
        XCTAssertEqual(sut.uiState.releaseStatus["com.a"]?.first?.versionName, "1.0", "The cached status still shows offline")
    }

    func testAccountWithoutTheVersionRuleShowsAndFetchesNoStatus() async throws {
        let imported = AccountModel(name: "Imported", providerType: .googlePlay,
                                    rules: AccountRules(apps: AccountPermission.allCases, review: [.view]), origin: .imported)
        let entry = GooglePlayReleaseSummariesCache(accountId: imported.id, packageName: "com.a",
                                                    summaries: [summary("production", "1", .published, "1")], fetchedAt: nil)
        try await storage.save(entry, id: entry.cacheKey)
        connection.fetchAppsHandler = { [app("com.a")] }
        let sut = makeSUT(account: imported)

        await sut.load()

        XCTAssertFalse(sut.uiState.canViewReleases)
        XCTAssertTrue(connection.releaseSummaryRequests.isEmpty)
        XCTAssertTrue(sut.uiState.releaseStatus.isEmpty)
    }

    func testAFailedTrackKeepsTheAppsCachedStatus() async throws {
        try await seedSummaries("com.a", [summary("production", "1.0 (10)", .inReview, "10")])
        connection.fetchAppsHandler = { [app("com.a"), app("com.b")] }
        connection.fetchReleaseSummariesHandler = { packageName, track in
            if packageName == "com.a", track == "beta" { throw StackError.Http(status: 500, message: "boom") }
            return [summary(track, "2.0 (20)", .published, "20")]
        }
        let sut = makeSUT()

        await sut.load()

        let cachedA = try await cachedSummaries("com.a")
        XCTAssertEqual(cachedA?.summaries.map(\.lifecycleState), [.inReview], "The failed app's cache is untouched")
        XCTAssertEqual(sut.uiState.releaseStatus["com.a"]?.map(\.lifecycleState), [.inReview])
        XCTAssertEqual(sut.uiState.releaseStatus["com.b"]?.count, 4, "Other apps still update")
        XCTAssertNil(sut.uiState.error, "Release status is best effort")
    }

    // MARK: - Search

    func testSearchMatchesNameOrPackage() async {
        connection.fetchAppsHandler = { [app("com.northwind.trailhead", name: "Trailhead"), app("com.northwind.ledger", name: "Ledger Pocket")] }
        let sut = makeSUT()
        await sut.load()

        sut.uiState.searchQuery = "ledger"
        XCTAssertEqual(sut.uiState.filteredApps.map(\.packageName), ["com.northwind.ledger"])
        sut.uiState.searchQuery = "TRAILHEAD"
        XCTAssertEqual(sut.uiState.filteredApps.map(\.title), ["Trailhead"])
        sut.uiState.searchQuery = "  "
        XCTAssertEqual(sut.uiState.filteredApps.count, 2)
    }
}

private func app(_ packageName: String, name: String? = nil) -> StackProtocols.AppInfo {
    StackProtocols.AppInfo(id: packageName, name: name ?? packageName, bundleId: packageName, platform: "ANDROID")
}

private func summary(_ track: String, _ name: String?, _ state: GooglePlayReleaseLifecycleState, _ code: String) -> GooglePlayReleaseSummaryModel {
    GooglePlayReleaseSummaryModel(track: track, name: name, lifecycleState: state, versionCodes: [code])
}
