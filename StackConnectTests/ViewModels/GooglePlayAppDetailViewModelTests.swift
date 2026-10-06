import XCTest
@testable import StackConnect

/// The Google Play app menu. Its key contract is the edit side-effect
/// mitigation: the screen itself never reads through a Play edit — it only reads
/// the local cache, and each edit-based section loads when the user opens it.
@MainActor
final class GooglePlayAppDetailViewModelTests: XCTestCase {

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
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        try await super.tearDown()
    }

    private func makeSUT(account: AccountModel? = nil) -> GooglePlayAppDetailViewModel {
        GooglePlayAppDetailViewModel(app: app, account: account ?? self.account, storage: storage)
    }

    private func importedAccount(
        apps: [AccountPermission] = AccountPermission.allCases,
        review: [AccountPermission] = AccountPermission.allCases,
        appsBundles: [String]? = nil
    ) -> AccountModel {
        AccountModel(
            name: "Imported",
            providerType: .googlePlay,
            rules: AccountRules(apps: apps, review: review),
            origin: .imported,
            appsBundles: appsBundles
        )
    }

    // MARK: - No auto-fetch

    /// Opening the menu, plus building every section ViewModel the menu can push
    /// (as SwiftUI does when it creates their `@StateObject`s), must not read
    /// through a Play edit. Only a section's own `load()` — run when that screen
    /// appears — may.
    func testMenuAndSectionCreationNeverReadThroughAPlayEdit() async throws {
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
        let sut = makeSUT()

        await sut.load()
        for section in GooglePlayAppDetailSection.allCases {
            XCTAssertNil(sut.denial(for: section))
        }
        let listings = GooglePlayStoreListingsViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.storeListingsFactory)
        let tracks = GooglePlayTracksViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.tracksFactory)
        let details = GooglePlayAppInfoViewModel(app: app, account: account, keychain: keychain, storage: storage, connectionFactory: connection.appDetailsFactory)
        await Task.yield()

        XCTAssertEqual(connection.editBasedReadCount, 0)
        XCTAssertTrue(connection.credentials.isEmpty, "No connection was even built")

        // Opening one section reads that section only.
        await tracks.load()
        XCTAssertEqual(connection.tracksRequests, ["com.example.app"])
        XCTAssertTrue(connection.storeListingsRequests.isEmpty)
        XCTAssertTrue(connection.appDetailsRequests.isEmpty)
        _ = (listings, details)
    }

    func testLoadReadsTheDefaultLanguageFromTheCacheOnly() async throws {
        let entry = GooglePlayAppDetailsCache(
            accountId: account.id,
            packageName: app.packageName,
            details: GooglePlayAppDetailsModel(packageName: app.packageName, defaultLanguage: "en-GB")
        )
        try await storage.save(entry, id: entry.cacheKey)
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.defaultLanguage, "en-GB")
    }

    func testLoadWithoutCacheLeavesTheDefaultLanguageUnknown() async {
        let sut = makeSUT()

        await sut.load()

        XCTAssertNil(sut.uiState.defaultLanguage)
    }

    func testMenuGroupsTheEditBasedSectionsTogether() {
        let state = makeSUT().uiState

        XCTAssertEqual(state.reviewSections, [.ratingsReviews])
        XCTAssertEqual(state.storeSections, [.storeListings, .tracks, .appDetails])
        XCTAssertTrue(state.storeSections.allSatisfy(\.opensPlayEdit))
        XCTAssertFalse(GooglePlayAppDetailSection.ratingsReviews.opensPlayEdit)
    }

    // MARK: - Permissions and scope

    func testCreatedAccountOpensEverySection() {
        let sut = makeSUT()

        for section in GooglePlayAppDetailSection.allCases {
            XCTAssertNil(sut.denial(for: section), "\(section)")
        }
        XCTAssertNil(sut.uiState.permissionDeniedMessage)
    }

    func testReviewsNeedTheReviewViewRule() {
        let sut = makeSUT(account: importedAccount(review: []))

        XCTAssertEqual(
            sut.denial(for: .ratingsReviews),
            String(localized: "You don't have permission to view ratings and reviews.")
        )
        XCTAssertNil(sut.denial(for: .storeListings), "Store sections follow the apps rule")
    }

    func testStoreSectionsNeedTheAppsViewRule() {
        let sut = makeSUT(account: importedAccount(apps: [], review: [.view]))

        for section in [GooglePlayAppDetailSection.storeListings, .tracks, .appDetails] {
            XCTAssertEqual(
                sut.denial(for: section),
                String(localized: "You don't have permission to view this app's details."),
                "\(section)"
            )
        }
        XCTAssertNil(sut.denial(for: .ratingsReviews))
    }

    /// Asking is a pure query; only `presentDenial` shows the alert.
    func testDenialIsAPureQueryAndPresentingIsExplicit() {
        let sut = makeSUT(account: importedAccount(review: []))

        let denial = sut.denial(for: .ratingsReviews)
        XCTAssertNotNil(denial)
        XCTAssertNil(sut.uiState.permissionDeniedMessage, "Querying never changes state")

        sut.presentDenial(denial ?? "")
        XCTAssertEqual(sut.uiState.permissionDeniedMessage, denial)
    }

    func testAppOutsideTheImportedScopeOpensNothingAndReadsNoCache() async throws {
        let scoped = importedAccount(appsBundles: ["com.other.app"])
        let entry = GooglePlayAppDetailsCache(
            accountId: scoped.id,
            packageName: app.packageName,
            details: GooglePlayAppDetailsModel(packageName: app.packageName, defaultLanguage: "en-GB")
        )
        try await storage.save(entry, id: entry.cacheKey)
        let sut = makeSUT(account: scoped)

        await sut.load()

        XCTAssertFalse(sut.uiState.isAppInScope)
        XCTAssertNil(sut.uiState.defaultLanguage)
        for section in GooglePlayAppDetailSection.allCases {
            XCTAssertEqual(
                sut.denial(for: section),
                String(localized: "This app isn't included in the apps shared with this account.")
            )
        }
    }

    func testAppInsideTheImportedScopeIsAvailable() {
        let sut = makeSUT(account: importedAccount(appsBundles: ["com.example.app"]))

        XCTAssertTrue(sut.uiState.isAppInScope)
        XCTAssertNil(sut.denial(for: .tracks))
    }
}
