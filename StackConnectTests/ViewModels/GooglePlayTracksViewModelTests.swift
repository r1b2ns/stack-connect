import XCTest
import StackCoreRust
@testable import StackConnect

@MainActor
final class GooglePlayTracksViewModelTests: XCTestCase {

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
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT() -> GooglePlayTracksViewModel {
        GooglePlayTracksViewModel(
            app: app,
            account: account,
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.tracksFactory
        )
    }

    private func seedTracks(_ tracks: [GooglePlayTrackModel]) async throws {
        let entry = GooglePlayTracksCache(accountId: account.id, packageName: app.packageName, tracks: tracks)
        try await storage.save(entry, id: entry.cacheKey)
    }

    private func cachedTracks() async throws -> [GooglePlayTrackModel]? {
        try await storage.fetch(
            GooglePlayTracksCache.self,
            id: GooglePlayTracksCache.cacheKey(accountId: account.id, packageName: app.packageName)
        )?.tracks
    }

    // MARK: - Tests

    func testInitDoesNotReadThroughAPlayEdit() async {
        _ = makeSUT()
        await Task.yield()

        XCTAssertEqual(connection.editBasedReadCount, 0)
    }

    func testLoadShowsTheCacheBeforeSyncingAndPersistsSortedTracks() async throws {
        try await seedTracks([makeTrack("production", releases: [makeRelease("1.0", status: .completed)])])
        let sut = makeSUT()
        connection.fetchTracksHandler = { _ in
            let (names, toast) = await MainActor.run { (sut.uiState.tracks?.map(\.track), sut.uiState.showSyncToast) }
            XCTAssertEqual(names, ["production"])
            XCTAssertTrue(toast)
            return [
                makeTrack("internal"),
                makeTrack("my-custom-qa"),
                makeTrack("beta"),
                makeTrack("production", releases: [makeRelease("1.1", status: .inProgress, fraction: 0.25)]),
                makeTrack("alpha")
            ]
        }

        await sut.load()

        XCTAssertEqual(
            sut.uiState.tracks?.map(\.track),
            ["production", "beta", "alpha", "internal", "my-custom-qa"],
            "Production, open, closed, internal testing, then custom tracks"
        )
        let production = try XCTUnwrap(sut.uiState.tracks?.first)
        XCTAssertEqual(production.releases.first?.status, .inProgress)
        XCTAssertEqual(production.releases.first?.rolloutFraction, 0.25)
        XCTAssertNil(sut.uiState.error)
        XCTAssertEqual(connection.tracksRequests, ["com.example.app"])
        let cached = try await cachedTracks()
        XCTAssertEqual(cached?.count, 5)
    }

    func testFailedSyncKeepsTheCachedTracks() async throws {
        try await seedTracks([makeTrack("production")])
        connection.fetchTracksHandler = { _ in
            throw StackError.Auth(message: "The service account has no access to com.example.app.")
        }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.tracks?.map(\.track), ["production"])
        XCTAssertEqual(
            sut.uiState.error,
            String(localized: "Google Play denied access to this service account.") + "\nThe service account has no access to com.example.app."
        )
    }

    func testOfflineWithCacheKeepsItSilently() async throws {
        try await seedTracks([makeTrack("production")])
        connection.fetchTracksHandler = { _ in throw StackError.Network(message: "offline") }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.tracks?.map(\.track), ["production"])
        XCTAssertNil(sut.uiState.error)
    }

    /// An edit read 404 can be an invalidated edit, not an unknown package.
    func testNotFoundWithoutCacheShowsTheGenericLoadError() async {
        connection.fetchTracksHandler = { _ in throw StackError.Http(status: 404, message: "") }
        let sut = makeSUT()

        await sut.load()

        XCTAssertNil(sut.uiState.tracks)
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertEqual(
            sut.uiState.error,
            String(localized: "Google Play couldn't load this information. Try again in a moment.")
        )
    }

    func testReturningFromAReleaseDoesNotReadAgain() async {
        let sut = makeSUT()

        await sut.loadIfNeeded()
        await sut.loadIfNeeded()

        XCTAssertEqual(connection.tracksRequests, ["com.example.app"])
    }
}

// MARK: - Fixtures

/// File-scope (nonisolated) so the `@Sendable` mock handlers can build them too.
private func makeTrack(_ name: String, releases: [GooglePlayReleaseModel] = []) -> GooglePlayTrackModel {
    GooglePlayTrackModel(track: name, releases: releases)
}

private func makeRelease(_ name: String, status: GooglePlayReleaseStatus, fraction: Double? = nil) -> GooglePlayReleaseModel {
    GooglePlayReleaseModel(
        name: name,
        status: status,
        versionCodes: ["42"],
        userFraction: fraction,
        releaseNotes: [GooglePlayLocalizedTextModel(language: "en-US", text: "Notes")],
        inAppUpdatePriority: 2
    )
}
