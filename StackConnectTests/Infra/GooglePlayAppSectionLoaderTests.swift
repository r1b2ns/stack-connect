import XCTest
import StackCoreRust
import StackProtocols
@testable import StackConnect

/// The loader behind every edit-based Google Play section (store listings,
/// tracks, app details). Each live read opens a Play edit, which cancels any
/// edit the same service account has open for the app (D14), so the contract
/// is: once per screen, never two at a time, never without access.
@MainActor
final class GooglePlayAppSectionLoaderTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayAccountConnection!

    private let account = AccountModel(name: "Play Team", providerType: .googlePlay)
    private let app = GooglePlayAppItem(id: "com.example.app", packageName: "com.example.app", title: "Example", isManuallyAdded: false)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayAccountConnection()
        storeCredentials(for: account)
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func storeCredentials(for account: AccountModel) {
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
    }

    private func makeLoader(
        screen: AnalyticsScreen? = nil,
        analytics: MockAnalyticsTracker = MockAnalyticsTracker()
    ) -> GooglePlayAppSectionLoader<GooglePlayTracksCache, any GooglePlayTracksFetching> {
        GooglePlayAppSectionLoader(
            account: account,
            app: app,
            logTag: "SectionLoaderTests",
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.tracksFactory,
            fetch: { connection, packageName in
                try await connection.fetchTracks(packageName: packageName)
            },
            screen: screen,
            analytics: analytics
        )
    }

    private func cachedTracks() async throws -> [GooglePlayTrackModel]? {
        try await storage.fetch(
            GooglePlayTracksCache.self,
            id: GooglePlayTracksCache.cacheKey(accountId: account.id, packageName: app.packageName)
        )?.tracks
    }

    // MARK: - Once per screen (B1)

    /// SwiftUI restarts a screen's `.task` when a pushed child pops back: a
    /// second `loadIfNeeded()` must not open another edit.
    func testLoadIfNeededReadsOnceAcrossRepeatedAppearances() async {
        let host = SectionHost()
        let loader = makeLoader()

        await loader.loadIfNeeded(into: host)
        await loader.loadIfNeeded(into: host)
        await loader.loadIfNeeded(into: host)

        XCTAssertEqual(connection.tracksRequests, ["com.example.app"], "Exactly one edit-based read")
        XCTAssertEqual(host.uiState.section.content, [])
    }

    func testRefreshStillReadsAfterLoadIfNeeded() async {
        let host = SectionHost()
        let loader = makeLoader()

        await loader.loadIfNeeded(into: host)
        await loader.load(into: host)
        await loader.loadIfNeeded(into: host)

        XCTAssertEqual(connection.tracksRequests.count, 2, "Pull to refresh reads again; appearing again doesn't")
    }

    /// A refresh (or Retry) while a read is in flight waits for it instead of
    /// opening a second edit that would invalidate the first.
    func testLoadWhileASyncIsInFlightDoesNotStartASecondOne() async {
        let gate = AsyncGate()
        connection.fetchTracksHandler = { _ in
            await gate.wait()
            return [GooglePlayTrackModel(track: "production", releases: [])]
        }
        let host = SectionHost()
        let loader = makeLoader()

        let first = Task { await loader.loadIfNeeded(into: host) }
        await gate.waitForArrivals()
        XCTAssertTrue(host.uiState.isSyncing, "isSyncing is the in-flight guard")

        let refresh = Task { await loader.load(into: host) }
        let retry = Task { await loader.load(into: host) }
        // Let both reach the in-flight guard while the first read is held.
        for _ in 0..<5 { await Task.yield() }
        await gate.open()
        await first.value
        await refresh.value
        await retry.value

        XCTAssertEqual(connection.tracksRequests.count, 1, "No overlapping edit-based reads")
        XCTAssertEqual(host.uiState.section.content?.map(\.track), ["production"])
        XCTAssertFalse(host.uiState.isSyncing)

        // Once it finished, a refresh reads again.
        await loader.load(into: host)
        XCTAssertEqual(connection.tracksRequests.count, 2)
    }

    /// The core serialises edit sessions per provider, so every read of one
    /// screen must go through the same connection.
    func testConnectionIsBuiltOnceAndReused() async {
        let host = SectionHost()
        let loader = makeLoader()

        await loader.loadIfNeeded(into: host)
        await loader.load(into: host)
        await loader.load(into: host)

        XCTAssertEqual(connection.tracksRequests.count, 3)
        XCTAssertEqual(connection.credentials.count, 1, "One connection per loader")
    }

    /// The screen's `.task` is cancelled when a child is pushed: the read keeps
    /// going and lands in the state and the cache.
    func testCallerCancellationDoesNotCutTheLoadShort() async throws {
        let gate = AsyncGate()
        let readWasCancelled = LockedFlag()
        connection.fetchTracksHandler = { _ in
            await gate.wait()
            readWasCancelled.set(Task.isCancelled)
            return [GooglePlayTrackModel(track: "beta", releases: [])]
        }
        let host = SectionHost()
        let loader = makeLoader()

        let screenTask = Task { await loader.loadIfNeeded(into: host) }
        await gate.waitForArrivals()
        screenTask.cancel()
        await gate.open()
        await screenTask.value

        XCTAssertFalse(readWasCancelled.value, "The read runs in the loader's own task")
        XCTAssertEqual(host.uiState.section.content?.map(\.track), ["beta"])
        XCTAssertFalse(host.uiState.isSyncing)
        let cached = try await cachedTracks()
        XCTAssertEqual(cached?.map(\.track), ["beta"])

        // Coming back to the screen doesn't read again.
        await loader.loadIfNeeded(into: host)
        XCTAssertEqual(connection.tracksRequests.count, 1)
    }

    func testIsSyncingCoversTheLiveRead() async {
        let host = SectionHost()
        connection.fetchTracksHandler = { _ in
            let syncing = await MainActor.run { host.uiState.isSyncing }
            XCTAssertTrue(syncing)
            return []
        }

        await makeLoader().load(into: host)

        XCTAssertFalse(host.uiState.isSyncing)
    }

    func testPreparesBeforeReadingAndPresentsCachedAndLiveContent() async throws {
        let entry = GooglePlayTracksCache(accountId: account.id, packageName: app.packageName, tracks: [
            GooglePlayTrackModel(track: "beta", releases: []),
            GooglePlayTrackModel(track: "production", releases: [])
        ])
        try await storage.save(entry, id: entry.cacheKey)
        let host = SectionHost()
        host.presentReversed = true
        connection.fetchTracksHandler = { _ in
            let (prepared, shown) = await MainActor.run { (host.prepareCount, host.uiState.section.content?.map(\.track)) }
            XCTAssertEqual(prepared, 1)
            XCTAssertEqual(shown, ["production", "beta"], "Cached content goes through present(_:)")
            return [GooglePlayTrackModel(track: "alpha", releases: []), GooglePlayTrackModel(track: "internal", releases: [])]
        }

        await makeLoader().load(into: host)

        XCTAssertEqual(host.uiState.section.content?.map(\.track), ["internal", "alpha"], "Live content too")
        let cached = try await cachedTracks()
        XCTAssertEqual(cached?.map(\.track), ["alpha", "internal"], "The cache keeps what the API returned")
    }

    // MARK: - Errors (S3)

    /// A 404 from an edit-based read can be the edit itself, invalidated by
    /// another edit — it isn't reported as an unknown package.
    func testNotFoundFromAnEditReadUsesTheGenericCopy() async {
        connection.fetchTracksHandler = { _ in throw StackError.Http(status: 404, message: "Edit not found") }
        let host = SectionHost()

        await makeLoader().load(into: host)

        XCTAssertNil(host.uiState.section.content)
        XCTAssertFalse(host.uiState.isLoading)
        XCTAssertEqual(host.uiState.error, String(localized: "Google Play couldn't load this information. Try again in a moment."))
    }

    // MARK: - Guards, for every section (moved from the section ViewModel tests)

    func testMissingCredentialsNeverReadsAnySection() async {
        keychain.removeObject(forKey: "credentials.\(account.id)")

        let errors = await loadEverySection(account: account)

        XCTAssertEqual(errors, [String?](repeating: String(localized: "No credentials found for this account."), count: 3))
        XCTAssertEqual(connection.editBasedReadCount, 0)
        XCTAssertTrue(connection.credentials.isEmpty)
    }

    func testAppOutsideAnImportedAccountsScopeNeverReadsAnySection() async {
        let scoped = AccountModel(name: "Imported", providerType: .googlePlay, origin: .imported, appsBundles: ["com.other.app"])
        storeCredentials(for: scoped)

        let errors = await loadEverySection(account: scoped)

        XCTAssertEqual(errors, [String?](repeating: String(localized: "This app isn't included in the apps shared with this account."), count: 3))
        XCTAssertEqual(connection.editBasedReadCount, 0)
    }

    /// Store listings and app details follow the `apps` rule; tracks follow
    /// `version` (plan R5). Neither rule: no section reads.
    func testAccountWithoutTheAppsAndVersionViewRulesNeverReadsAnySection() async {
        let restricted = AccountModel(
            name: "Imported",
            providerType: .googlePlay,
            rules: AccountRules(apps: [], review: [.view]),
            origin: .imported
        )
        storeCredentials(for: restricted)

        let errors = await loadEverySection(account: restricted)

        let details = String(localized: "You don't have permission to view this app's details.")
        let releases = String(localized: "You don't have permission to view this app's releases.")
        XCTAssertEqual(errors, [details, releases, details])
        XCTAssertEqual(connection.editBasedReadCount, 0)
    }

    /// Each section ViewModel wires its screen's `loadIfNeeded()` to the loader.
    func testEverySectionViewModelReadsOncePerScreen() async {
        let listings = GooglePlayStoreListingsViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.storeListingsFactory)
        let tracks = GooglePlayTracksViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.tracksFactory)
        let details = GooglePlayAppInfoViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.appDetailsFactory)

        for _ in 0..<2 {
            await listings.loadIfNeeded()
            await tracks.loadIfNeeded()
            await details.loadIfNeeded()
        }

        XCTAssertEqual(connection.storeListingsRequests.count, 1)
        XCTAssertEqual(connection.tracksRequests.count, 1)
        XCTAssertEqual(connection.appDetailsRequests.count, 1)

        await tracks.load()
        XCTAssertEqual(connection.tracksRequests.count, 2, "Refresh reads that section again")
    }

    /// Opens every section screen once for `account`; returns their errors
    /// (store listings, tracks, app details).
    private func loadEverySection(account: AccountModel) async -> [String?] {
        let listings = GooglePlayStoreListingsViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.storeListingsFactory)
        let tracks = GooglePlayTracksViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.tracksFactory)
        let details = GooglePlayAppInfoViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.appDetailsFactory)

        await listings.loadIfNeeded()
        await tracks.loadIfNeeded()
        await details.loadIfNeeded()

        return [listings.uiState.error, tracks.uiState.error, details.uiState.error]
    }

    // MARK: - Analytics

    func testFirstLoadAndRefreshAreTrackedOnTheScreen() async {
        let analytics = MockAnalyticsTracker()
        let host = SectionHost()
        let loader = makeLoader(screen: .googlePlayTracks, analytics: analytics)

        await loader.loadIfNeeded(into: host)
        await loader.loadIfNeeded(into: host)
        await loader.load(into: host)

        XCTAssertEqual(analytics.results(of: .load), [.success], "Appearing again reads nothing, tracks nothing")
        XCTAssertEqual(analytics.results(of: .refresh), [.success])
        XCTAssertEqual(analytics.actions(of: .load).first?.parameters["screen_name"], .string("google_play_tracks"))
    }

    func testFailedLoadIsTrackedWithItsCategoryAndKeptForErrorShown() async {
        connection.fetchTracksHandler = { _ in throw StackError.Http(status: 403, message: "The caller does not have permission") }
        let analytics = MockAnalyticsTracker()
        let host = SectionHost()
        let loader = makeLoader(screen: .googlePlayTracks, analytics: analytics)

        await loader.loadIfNeeded(into: host)

        XCTAssertEqual(analytics.results(of: .load), [.failure])
        XCTAssertEqual(analytics.actions(of: .load).first?.parameters["error_category"], .string("forbidden"))
        XCTAssertEqual(host.uiState.errorCategory, .forbidden)
        XCTAssertTrue(analytics.nonFatals.isEmpty, "Permission errors are expected, never non-fatals")
    }

    func testMissingCredentialsIsTrackedAsInvalidCredentials() async {
        keychain = MockKeyStorable()
        let analytics = MockAnalyticsTracker()
        let host = SectionHost()
        let loader = makeLoader(screen: .googlePlayTracks, analytics: analytics)

        await loader.loadIfNeeded(into: host)

        XCTAssertEqual(analytics.actions(of: .load).first?.parameters["error_category"], .string("invalid_credentials"))
        XCTAssertEqual(host.uiState.errorCategory, .invalidCredentials)
    }

    func testServerFailureIsRecordedAsANonFatal() async {
        connection.fetchTracksHandler = { _ in throw StackError.Http(status: 500, message: "Internal error") }
        let analytics = MockAnalyticsTracker()
        let loader = makeLoader(screen: .googlePlayTracks, analytics: analytics)

        await loader.loadIfNeeded(into: SectionHost())

        XCTAssertEqual(analytics.nonFatals.map(\.category), [.server])
    }

    func testWithoutAScreenNothingIsTracked() async {
        let analytics = MockAnalyticsTracker()
        let loader = makeLoader(analytics: analytics)

        await loader.loadIfNeeded(into: SectionHost())

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }
}

// MARK: - Test host

@MainActor
private final class SectionHost: GooglePlayAppSectionHosting {

    struct UiState: GooglePlayAppSectionUiState {
        var section = GooglePlayAppSectionState<[GooglePlayTrackModel]>()
    }

    var uiState = UiState()
    var prepareCount = 0
    var presentReversed = false

    func prepareLoad() async {
        prepareCount += 1
    }

    func present(_ content: [GooglePlayTrackModel]) -> [GooglePlayTrackModel] {
        presentReversed ? content.reversed() : content
    }
}
