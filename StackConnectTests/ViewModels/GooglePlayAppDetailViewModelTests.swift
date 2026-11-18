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
        version: [AccountPermission] = AccountPermission.allCases,
        review: [AccountPermission] = AccountPermission.allCases,
        appsBundles: [String]? = nil
    ) -> AccountModel {
        AccountModel(
            name: "Imported",
            providerType: .googlePlay,
            rules: AccountRules(apps: apps, version: version, review: review),
            origin: .imported,
            appsBundles: appsBundles
        )
    }

    // MARK: - Credential-aware copy

    func testStoreSectionsFooterFollowsTheAuthMethod() {
        XCTAssertEqual(
            makeSUT().uiState.storeSectionsFooter,
            String(localized: "Opening these sections briefly opens a Play edit to read the data. Google allows one open edit per service account and app, so this cancels any edit this service account has open for the app — for example, a CI upload in progress. If your CI publishes with this service account, add a separate read-only one here instead.")
        )
        let signIn = AccountModel(name: "Signed In", providerType: .googlePlay, authMethod: .googleSignIn)
        let footer = makeSUT(account: signIn).uiState.storeSectionsFooter
        XCTAssertEqual(
            footer,
            String(localized: "Opening these sections briefly opens a Play edit to read the data. Google allows one open edit per account and app, so this cancels any edit open with your Google account for the app.")
        )
        XCTAssertFalse(footer.localizedCaseInsensitiveContains("service account"))
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
        XCTAssertEqual(state.storeSections, [.storeListings, .appDetails], "Tracks open from See all tracks")
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

        for section in [GooglePlayAppDetailSection.storeListings, .appDetails] {
            XCTAssertEqual(
                sut.denial(for: section),
                String(localized: "You don't have permission to view this app's details."),
                "\(section)"
            )
        }
        XCTAssertNil(sut.denial(for: .ratingsReviews))
        XCTAssertNil(sut.denial(for: .tracks), "Tracks follow the version rule (R5)")
    }

    func testTracksNeedTheVersionViewRule() {
        let sut = makeSUT(account: importedAccount(version: []))

        XCTAssertEqual(GooglePlayAppDetailSection.tracks.requiredResource, .version)
        XCTAssertEqual(
            sut.denial(for: .tracks),
            String(localized: "You don't have permission to view this app's releases.")
        )
        XCTAssertNil(sut.denial(for: .storeListings))
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
    // MARK: - Release sections (cache only)

    private func seedReleaseSummaries(_ summaries: [GooglePlayReleaseSummaryModel], account: AccountModel? = nil) async throws {
        let entry = GooglePlayReleaseSummariesCache(accountId: (account ?? self.account).id, packageName: app.packageName, summaries: summaries, fetchedAt: nil)
        try await storage.save(entry, id: entry.cacheKey)
    }

    private func seedTracks(_ tracks: [GooglePlayTrackModel]) async throws {
        let entry = GooglePlayTracksCache(accountId: account.id, packageName: app.packageName, tracks: tracks)
        try await storage.save(entry, id: entry.cacheKey)
    }

    func testReleaseSectionsComeFromTheSummariesAndTheTracksCacheAddsStatusAndRollout() async throws {
        try await seedReleaseSummaries([
            GooglePlayReleaseSummaryModel(track: "internal", name: "4.3.0 (4305)", lifecycleState: .draft, versionCodes: ["4305"]),
            GooglePlayReleaseSummaryModel(track: "internal", name: "4.3.0 (4303)", lifecycleState: .published, versionCodes: ["4303"]),
            GooglePlayReleaseSummaryModel(track: "production", name: "4.1.2 (4122)", lifecycleState: .published, versionCodes: ["4122"]),
            GooglePlayReleaseSummaryModel(track: "production", name: "4.2.0 (4210)", lifecycleState: .inReview, versionCodes: ["4210"])
        ])
        try await seedTracks([GooglePlayTrackModel(track: "production", releases: [
            GooglePlayReleaseModel(name: "4.2.0 (4210)", status: .inProgress, versionCodes: ["4210"], userFraction: 0.2, releaseNotes: [], inAppUpdatePriority: nil)
        ])])
        let sut = makeSUT()

        await sut.load()

        let sections = sut.uiState.releaseSections
        XCTAssertEqual(sections.map(\.track), ["production", "internal"])
        let rollout = try XCTUnwrap(sections.first?.rows.first)
        XCTAssertEqual(rollout.title, "4.2.0")
        XCTAssertEqual(rollout.lifecycleState, .inReview)
        XCTAssertEqual(rollout.status, .inProgress)
        XCTAssertEqual(rollout.rolloutFraction, 0.2)
        let published = try XCTUnwrap(sections.first?.rows.last)
        XCTAssertNil(published.status, "Not in the tracks cache: no badge")
        XCTAssertNil(published.rolloutFraction)
        XCTAssertEqual(sections.last?.rows.map(\.title), ["4.3.0 (4305)", "4.3.0 (4303)"], "Same short name: full names")
        XCTAssertEqual(connection.editBasedReadCount, 0)
    }

    func testWithoutSummariesTheTracksCacheAloneBuildsTheSections() async throws {
        try await seedTracks([
            GooglePlayTrackModel(track: "internal", releases: []),
            GooglePlayTrackModel(track: "beta", releases: [
                GooglePlayReleaseModel(name: "2.0 (20)", status: .completed, versionCodes: ["20"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)
            ])
        ])
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.releaseSections.map(\.track), ["beta"], "Tracks without a release are left out")
        XCTAssertNil(sut.uiState.releaseSections.first?.rows.first?.lifecycleState)
        XCTAssertEqual(sut.uiState.releaseSections.first?.rows.first?.status, .completed)
    }

    func testNoCacheMeansNoReleaseSections() async {
        let sut = makeSUT()

        await sut.load()

        XCTAssertTrue(sut.uiState.releaseSections.isEmpty)
        XCTAssertTrue(sut.uiState.canViewReleases)
    }

    func testAccountWithoutTheVersionRuleShowsNoReleases() async throws {
        let imported = importedAccount(version: [])
        try await seedReleaseSummaries([
            GooglePlayReleaseSummaryModel(track: "production", name: "1", lifecycleState: .published, versionCodes: ["1"])
        ], account: imported)
        let sut = makeSUT(account: imported)

        await sut.load()

        XCTAssertFalse(sut.uiState.canViewReleases)
        XCTAssertTrue(sut.uiState.releaseSections.isEmpty)
    }
}
