import XCTest
import StackCoreRust
@testable import StackConnect

@MainActor
final class GooglePlayAppInfoViewModelTests: XCTestCase {

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

    private func makeSUT() -> GooglePlayAppInfoViewModel {
        GooglePlayAppInfoViewModel(
            app: app,
            account: account,
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.appDetailsFactory
        )
    }

    private func seedDetails(_ details: GooglePlayAppDetailsModel) async throws {
        let entry = GooglePlayAppDetailsCache(accountId: account.id, packageName: app.packageName, details: details)
        try await storage.save(entry, id: entry.cacheKey)
    }

    private func cachedDetails() async throws -> GooglePlayAppDetailsModel? {
        try await storage.fetch(
            GooglePlayAppDetailsCache.self,
            id: GooglePlayAppDetailsCache.cacheKey(accountId: account.id, packageName: app.packageName)
        )?.details
    }

    // MARK: - Tests

    func testInitDoesNotReadThroughAPlayEdit() async {
        _ = makeSUT()
        await Task.yield()

        XCTAssertEqual(connection.editBasedReadCount, 0)
    }

    func testLoadShowsTheCacheBeforeSyncingAndPersistsTheResult() async throws {
        try await seedDetails(makeDetails(email: "old@example.com"))
        let sut = makeSUT()
        connection.fetchAppDetailsHandler = { _ in
            let (email, toast) = await MainActor.run { (sut.uiState.details?.contactEmail, sut.uiState.showSyncToast) }
            XCTAssertEqual(email, "old@example.com")
            XCTAssertTrue(toast)
            return makeDetails(email: "new@example.com")
        }

        await sut.load()

        XCTAssertEqual(sut.uiState.details?.contactEmail, "new@example.com")
        XCTAssertNil(sut.uiState.error)
        XCTAssertEqual(connection.appDetailsRequests, ["com.example.app"])
        let cached = try await cachedDetails()
        XCTAssertEqual(cached?.contactEmail, "new@example.com")
    }

    func testFailedSyncKeepsTheCachedDetails() async throws {
        try await seedDetails(makeDetails(email: "old@example.com"))
        connection.fetchAppDetailsHandler = { _ in throw StackError.Http(status: 429, message: "") }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.details?.contactEmail, "old@example.com")
        XCTAssertEqual(sut.uiState.error, String(localized: "You hit Google's rate limit. Wait a moment and try again."))
    }

    func testOfflineWithoutCacheShowsTheOfflineError() async {
        connection.fetchAppDetailsHandler = { _ in throw OfflineError.noConnection }
        let sut = makeSUT()

        await sut.load()

        XCTAssertNil(sut.uiState.details)
        XCTAssertEqual(sut.uiState.error, OfflineError.noConnection.localizedDescription)
    }

    func testLoadIfNeededReadsOnce() async {
        let sut = makeSUT()

        await sut.loadIfNeeded()
        await sut.loadIfNeeded()

        XCTAssertEqual(connection.appDetailsRequests, ["com.example.app"])
    }

    /// The App Details cache feeds the Store Listings default language.
    func testSyncedDetailsGiveStoreListingsTheirDefaultLanguage() async {
        connection.fetchAppDetailsHandler = { _ in
            GooglePlayAppDetailsModel(packageName: "com.example.app", defaultLanguage: "de-DE")
        }
        await makeSUT().load()
        connection.fetchStoreListingsHandler = { _ in
            [
                GooglePlayStoreListingModel(language: "en-US", title: nil, shortDescription: nil, fullDescription: nil, video: nil),
                GooglePlayStoreListingModel(language: "de-DE", title: nil, shortDescription: nil, fullDescription: nil, video: nil)
            ]
        }
        let listings = GooglePlayStoreListingsViewModel(
            app: app,
            account: account,
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.storeListingsFactory
        )

        await listings.load()

        XCTAssertEqual(listings.uiState.defaultLanguage, "de-DE")
        XCTAssertEqual(listings.uiState.listings?.first?.language, "de-DE")
    }
}

// MARK: - Fixtures

/// File-scope (nonisolated) so the `@Sendable` mock handlers can build them too.
private func makeDetails(email: String?) -> GooglePlayAppDetailsModel {
    GooglePlayAppDetailsModel(
        packageName: "com.example.app",
        defaultLanguage: "en-US",
        contactEmail: email,
        contactPhone: "+1 555 0100",
        contactWebsite: "example.com"
    )
}
