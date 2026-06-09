import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsAppDetailModel` (T-W11).
/// Covers: offline-first load (TC-014), sections data (TC-015),
/// favorite toggle + persistence (TC-020), archive + persistence (TC-021),
/// and network failure with cached fallback (TC-022).
@MainActor
final class WindowsAppDetailModelTests: XCTestCase {

    private var storage: MockStorage!
    private var connection: MockAppleConnection!
    private let accountId = "acct-001"

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorage()
        connection = MockAppleConnection()
    }

    override func tearDown() async throws {
        storage = nil
        connection = nil
        try await super.tearDown()
    }

    /// Helper: creates a SUT with the shared storage + connection.
    private func makeSUT(
        withConnection: Bool = true
    ) -> WindowsAppDetailModel {
        WindowsAppDetailModel(
            storage: storage,
            connection: withConnection ? connection : nil
        )
    }

    /// Helper: seeds an app into storage.
    private func seedApp(_ app: AppModel) async {
        try! await storage.save(app, id: "\(app.accountId).\(app.id)")
    }

    /// Helper: creates a standard test app.
    private func makeApp(
        id: String = "app-001",
        name: String = "MyApp",
        bundleId: String = "com.example",
        accountId: String = "acct-001",
        iconUrl: String? = "https://example.com/icon.png",
        appStoreState: AppStoreState? = .readyForSale,
        versionString: String? = "2.1.0",
        isFavorite: Bool = false,
        isArchived: Bool = false
    ) -> AppModel {
        AppModel(
            id: id,
            name: name,
            bundleId: bundleId,
            accountId: accountId,
            iconUrl: iconUrl,
            appStoreState: appStoreState,
            versionString: versionString,
            isArchived: isArchived,
            isFavorite: isFavorite
        )
    }

    // MARK: - TC-014: loadAppIfNeeded populates header data

    func testLoadAppPopulatesHeaderData() async {
        // Given: a cached app with full header data
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        // Then: header data is populated
        let loaded = sut.uiState.app
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "MyApp")
        XCTAssertEqual(loaded?.bundleId, "com.example")
        XCTAssertEqual(loaded?.appStoreState, .readyForSale)
        XCTAssertEqual(loaded?.appStoreState?.displayName, "Ready for Sale")
        XCTAssertEqual(loaded?.appStoreState?.color, .green)
        XCTAssertEqual(loaded?.versionString, "2.1.0")
        XCTAssertEqual(loaded?.iconUrl, "https://example.com/icon.png")
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertNil(sut.uiState.syncError)
    }

    // MARK: - TC-015: uiState.sections contains the 4 sections with correct option titles

    func testSectionsContainCorrectStructure() async {
        // Given: a cached app
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        let sections = sut.uiState.sections
        XCTAssertEqual(sections.count, 4)

        // Section 1: General
        XCTAssertEqual(sections[0].title, "General")
        XCTAssertEqual(sections[0].options.count, 3)
        XCTAssertEqual(sections[0].options[0].title, "App Information")
        XCTAssertEqual(sections[0].options[1].title, "App Review")
        XCTAssertEqual(sections[0].options[2].title, "History")

        // Section 2: App Store
        XCTAssertEqual(sections[1].title, "App Store")
        XCTAssertEqual(sections[1].options.count, 3)
        XCTAssertEqual(sections[1].options[0].title, "App Privacy")
        XCTAssertEqual(sections[1].options[1].title, "App Accessibility")
        XCTAssertEqual(sections[1].options[2].title, "Ratings and Reviews")

        // Section 3: Analytics
        XCTAssertEqual(sections[2].title, "Analytics")
        XCTAssertEqual(sections[2].options.count, 0)

        // Section 4: TestFlight
        XCTAssertEqual(sections[3].title, "TestFlight")
        XCTAssertEqual(sections[3].options.count, 0)
    }

    // MARK: - AC-W06-3: Coming-soon vs functional options

    func testOnlyRatingsAndReviewsIsFunctional() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        let sections = sut.uiState.sections
        let allOptions = sections.flatMap { $0.options }

        // Only "Ratings and Reviews" should be functional
        let functionalOptions = allOptions.filter { $0.isFunctional }
        XCTAssertEqual(functionalOptions.count, 1)
        XCTAssertEqual(functionalOptions.first?.title, "Ratings and Reviews")

        // All others are coming-soon (not functional)
        let comingSoonOptions = allOptions.filter { !$0.isFunctional }
        XCTAssertEqual(comingSoonOptions.count, 5)
        let comingSoonTitles = comingSoonOptions.map { $0.title }
        XCTAssertTrue(comingSoonTitles.contains("App Information"))
        XCTAssertTrue(comingSoonTitles.contains("App Review"))
        XCTAssertTrue(comingSoonTitles.contains("History"))
        XCTAssertTrue(comingSoonTitles.contains("App Privacy"))
        XCTAssertTrue(comingSoonTitles.contains("App Accessibility"))
    }

    // MARK: - TC-020: toggleFavorite flips isFavorite, persists, and toggling again reverts

    func testToggleFavoritePersistsAndTogglesBack() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)
        XCTAssertFalse(sut.uiState.app!.isFavorite)

        // Toggle ON
        await sut.toggleFavorite(appId: "app-001")
        XCTAssertTrue(sut.uiState.app!.isFavorite)

        // Verify persistence: a new model instance should see the favorited state
        let sut2 = makeSUT(withConnection: false)
        await sut2.loadAppIfNeeded(appId: "app-001", accountId: accountId)
        XCTAssertTrue(sut2.uiState.app!.isFavorite)

        // Toggle OFF
        await sut.toggleFavorite(appId: "app-001")
        XCTAssertFalse(sut.uiState.app!.isFavorite)

        // Verify persistence again
        let sut3 = makeSUT(withConnection: false)
        await sut3.loadAppIfNeeded(appId: "app-001", accountId: accountId)
        XCTAssertFalse(sut3.uiState.app!.isFavorite)
    }

    // MARK: - TC-021: archiveApp sets isArchived and persists

    func testArchiveAppSetsIsArchivedAndPersists() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)
        XCTAssertFalse(sut.uiState.app!.isArchived)

        // Archive
        await sut.archiveApp(appId: "app-001", accountId: accountId)
        XCTAssertTrue(sut.uiState.app!.isArchived)

        // Verify persistence: a new model instance should see the archived state
        let sut2 = makeSUT(withConnection: false)
        await sut2.loadAppIfNeeded(appId: "app-001", accountId: accountId)
        XCTAssertTrue(sut2.uiState.app!.isArchived)
    }

    // MARK: - TC-022: Network failure keeps cached detail and sets error

    func testNetworkFailureKeepsCachedDetailAndSetsError() async {
        // Given: a cached app
        let app = makeApp()
        await seedApp(app)

        // Connection will throw
        connection.fetchAppsResult = .failure(NSError(domain: "net", code: -1))

        let sut = makeSUT()
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        // Then: cached app is still shown
        XCTAssertNotNil(sut.uiState.app)
        XCTAssertEqual(sut.uiState.app?.name, "MyApp")
        XCTAssertEqual(sut.uiState.app?.bundleId, "com.example")
        // Error is set
        XCTAssertNotNil(sut.uiState.syncError)
        XCTAssertEqual(sut.uiState.syncError, "Sync failed. Showing cached data.")
        // Loading is done
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - Favorite toggle revert-on-failure

    func testToggleFavoriteRevertsOnPersistenceFailure() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)
        XCTAssertFalse(sut.uiState.app!.isFavorite)

        // Make save fail
        storage.shouldThrowOnSave = true
        await sut.toggleFavorite(appId: "app-001")

        // Reverted: still not favorite
        XCTAssertFalse(sut.uiState.app!.isFavorite)
        XCTAssertNotNil(sut.uiState.syncError)
        XCTAssertEqual(sut.uiState.syncError, "Failed to update favorite.")
    }

    // MARK: - Archive revert-on-failure

    func testArchiveRevertsOnPersistenceFailure() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        // Make save fail
        storage.shouldThrowOnSave = true
        await sut.archiveApp(appId: "app-001", accountId: accountId)

        // Reverted: not archived, error set
        XCTAssertFalse(sut.uiState.app!.isArchived)
        XCTAssertNotNil(sut.uiState.syncError)
        XCTAssertEqual(sut.uiState.syncError, "Failed to archive app.")
    }

    // MARK: - Live refresh merges remote data with cached local flags

    func testLiveRefreshMergesRemoteWithCachedFlags() async {
        // Given: cached app with local flags
        let app = makeApp(isFavorite: true)
        await seedApp(app)

        // Remote returns the same app with a new name
        connection.fetchAppsResult = .success([
            AppInfo(id: "app-001", name: "MyApp Updated", bundleId: "com.example")
        ])

        let sut = makeSUT()
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        // Name updated from remote, local flags preserved
        XCTAssertEqual(sut.uiState.app?.name, "MyApp Updated")
        XCTAssertTrue(sut.uiState.app!.isFavorite)
        XCTAssertFalse(sut.uiState.app!.isArchived)
    }

    // MARK: - Empty cache with no connection

    func testEmptyCacheNoConnectionProducesNilApp() async {
        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        XCTAssertNil(sut.uiState.app)
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertNil(sut.uiState.syncError)
        // Sections should be empty since no app was loaded
        XCTAssertTrue(sut.uiState.sections.isEmpty)
    }

    // MARK: - buildSections is a static pure function

    func testBuildSectionsReturnsFourSections() {
        let sections = WindowsAppDetailModel.buildSections()
        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(sections[0].title, "General")
        XCTAssertEqual(sections[1].title, "App Store")
        XCTAssertEqual(sections[2].title, "Analytics")
        XCTAssertEqual(sections[3].title, "TestFlight")
    }

    // MARK: - toggleFavorite on mismatched appId is a no-op

    func testToggleFavoriteMismatchedAppIdIsNoOp() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        await sut.toggleFavorite(appId: "nonexistent")

        // No change
        XCTAssertFalse(sut.uiState.app!.isFavorite)
        XCTAssertNil(sut.uiState.syncError)
    }

    // MARK: - archiveApp on mismatched appId is a no-op

    func testArchiveMismatchedAppIdIsNoOp() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        await sut.archiveApp(appId: "nonexistent", accountId: accountId)

        // No change
        XCTAssertFalse(sut.uiState.app!.isArchived)
        XCTAssertNil(sut.uiState.syncError)
    }

    // MARK: - SF3: toggleFavorite clears pre-existing syncError

    func testToggleFavoriteClearsPreExistingSyncError() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        // Cause a syncError via a failed favorite toggle
        storage.shouldThrowOnSave = true
        await sut.toggleFavorite(appId: "app-001")
        XCTAssertNotNil(sut.uiState.syncError, "Precondition: syncError should be set")
        storage.shouldThrowOnSave = false

        // When: toggleFavorite is called again (successfully this time)
        await sut.toggleFavorite(appId: "app-001")

        // Then: syncError is cleared
        XCTAssertNil(sut.uiState.syncError, "toggleFavorite should clear pre-existing syncError")
    }

    // MARK: - SF3: archiveApp clears pre-existing syncError

    func testArchiveAppClearsPreExistingSyncError() async {
        let app = makeApp()
        await seedApp(app)

        let sut = makeSUT(withConnection: false)
        await sut.loadAppIfNeeded(appId: "app-001", accountId: accountId)

        // Cause a syncError via a failed favorite toggle
        storage.shouldThrowOnSave = true
        await sut.toggleFavorite(appId: "app-001")
        XCTAssertNotNil(sut.uiState.syncError, "Precondition: syncError should be set")
        storage.shouldThrowOnSave = false

        // When: archiveApp is called (successfully)
        await sut.archiveApp(appId: "app-001", accountId: accountId)

        // Then: syncError is cleared
        XCTAssertNil(sut.uiState.syncError, "archiveApp should clear pre-existing syncError")
    }
}
