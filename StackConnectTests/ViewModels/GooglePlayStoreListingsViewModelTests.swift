import XCTest
import StackCoreRust
@testable import StackConnect

@MainActor
final class GooglePlayStoreListingsViewModelTests: XCTestCase {

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

    private func makeSUT() -> GooglePlayStoreListingsViewModel {
        GooglePlayStoreListingsViewModel(
            app: app,
            account: account,
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.storeListingsFactory
        )
    }

    private func seedListings(_ listings: [GooglePlayStoreListingModel]) async throws {
        let entry = GooglePlayStoreListingsCache(accountId: account.id, packageName: app.packageName, listings: listings)
        try await storage.save(entry, id: entry.cacheKey)
    }

    private func seedDefaultLanguage(_ language: String) async throws {
        let entry = GooglePlayAppDetailsCache(
            accountId: account.id,
            packageName: app.packageName,
            details: GooglePlayAppDetailsModel(packageName: app.packageName, defaultLanguage: language)
        )
        try await storage.save(entry, id: entry.cacheKey)
    }

    private func cachedListings() async throws -> [GooglePlayStoreListingModel]? {
        try await storage.fetch(
            GooglePlayStoreListingsCache.self,
            id: GooglePlayStoreListingsCache.cacheKey(accountId: account.id, packageName: app.packageName)
        )?.listings
    }

    // MARK: - No auto-fetch

    func testInitDoesNotReadThroughAPlayEdit() async {
        _ = makeSUT()
        await Task.yield()

        XCTAssertEqual(connection.editBasedReadCount, 0, "Only an explicit load (opening the screen) may open a Play edit")
    }

    // MARK: - Offline-first

    func testLoadShowsTheCacheBeforeSyncingAndPersistsTheResult() async throws {
        try await seedListings([makeListing("en-US", title: "Cached")])
        let sut = makeSUT()
        connection.fetchStoreListingsHandler = { _ in
            let (titles, toast, loading) = await MainActor.run {
                (sut.uiState.listings?.map(\.title), sut.uiState.showSyncToast, sut.uiState.isLoading)
            }
            XCTAssertEqual(titles, ["Cached"])
            XCTAssertTrue(toast)
            XCTAssertFalse(loading, "Cached data must not hide behind a spinner")
            return [makeListing("en-US", title: "Fresh")]
        }

        await sut.load()

        XCTAssertEqual(sut.uiState.listings?.map(\.title), ["Fresh"])
        XCTAssertNil(sut.uiState.error)
        XCTAssertFalse(sut.uiState.isSyncing)
        XCTAssertEqual(connection.storeListingsRequests, ["com.example.app"])
        let cached = try await cachedListings()
        XCTAssertEqual(cached?.map(\.title), ["Fresh"])
    }

    func testDefaultLanguageFromCachedDetailsIsListedFirst() async throws {
        try await seedDefaultLanguage("pt-BR")
        connection.fetchStoreListingsHandler = { _ in
            [makeListing("en-US"), makeListing("de-DE"), makeListing("pt-BR")]
        }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.defaultLanguage, "pt-BR")
        XCTAssertEqual(sut.uiState.listings?.first?.language, "pt-BR")
        XCTAssertEqual(sut.uiState.listings?.count, 3)
    }

    func testWithoutCacheShowsSpinnerThenListings() async {
        let sut = makeSUT()
        connection.fetchStoreListingsHandler = { _ in
            let (loading, toast) = await MainActor.run { (sut.uiState.isLoading, sut.uiState.showSyncToast) }
            XCTAssertTrue(loading, "Nothing cached: spinner while the API answers")
            XCTAssertFalse(toast)
            return [makeListing("en-US")]
        }

        await sut.load()

        XCTAssertFalse(sut.uiState.showSyncToast, "No toast when nothing was cached")
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertEqual(sut.uiState.listings?.map(\.language), ["en-US"])
    }

    func testFailedSyncKeepsTheCacheAndShowsTheErrorInline() async throws {
        try await seedListings([makeListing("en-US", title: "Cached")])
        connection.fetchStoreListingsHandler = { _ in throw StackError.Http(status: 500, message: "") }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.listings?.map(\.title), ["Cached"])
        XCTAssertEqual(sut.uiState.error, String(localized: "Google Play is temporarily unavailable. Try again in a few minutes."))
        let cached = try await cachedListings()
        XCTAssertEqual(cached?.map(\.title), ["Cached"], "A failed sync never overwrites the cache")
    }

    func testOfflineWithCacheKeepsItWithoutAnExtraWarning() async throws {
        try await seedListings([makeListing("en-US", title: "Cached")])
        connection.fetchStoreListingsHandler = { _ in throw OfflineError.noConnection }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.listings?.map(\.title), ["Cached"])
        XCTAssertNil(sut.uiState.error, "The global offline banner already explains it")
    }

    func testOfflineWithoutCacheShowsTheOfflineError() async {
        connection.fetchStoreListingsHandler = { _ in throw OfflineError.noConnection }
        let sut = makeSUT()

        await sut.load()

        XCTAssertNil(sut.uiState.listings)
        XCTAssertEqual(sut.uiState.error, OfflineError.noConnection.localizedDescription)
    }

    // Credentials, per-app scope and the apps view rule are checked by the
    // shared `GooglePlayAppSectionLoader`, for every section:
    // see `GooglePlayAppSectionLoaderTests`.

    // MARK: - Once per screen

    func testReturningFromALanguageDoesNotReadAgain() async {
        let sut = makeSUT()

        await sut.loadIfNeeded()
        await sut.loadIfNeeded()

        XCTAssertEqual(connection.storeListingsRequests, ["com.example.app"])
    }
}

// MARK: - Fixtures

/// File-scope (nonisolated) so the `@Sendable` mock handlers can build them too.
private func makeListing(_ language: String, title: String? = nil) -> GooglePlayStoreListingModel {
    GooglePlayStoreListingModel(language: language, title: title, shortDescription: nil, fullDescription: nil, video: nil)
}
