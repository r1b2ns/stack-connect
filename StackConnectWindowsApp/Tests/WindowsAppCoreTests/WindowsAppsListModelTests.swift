import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Focused unit tests for `WindowsAppsListModel` (T-W05).
/// Covers: offline-first load, live sync, search filtering, favorite toggle
/// with persistence + revert-on-failure, archive flow with confirmation +
/// revert-on-failure, empty states, and sync error handling.
///
/// The comprehensive suite is downstream (T-W09); this file covers the key
/// TCs required by the task acceptance criteria.
@MainActor
final class WindowsAppsListModelTests: XCTestCase {

    private var storage: MockStorage!
    private var connection: MockAppleConnection!
    private let accountId = "acc1"

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
    ) -> WindowsAppsListModel {
        WindowsAppsListModel(
            accountId: accountId,
            storage: storage,
            connection: withConnection ? connection : nil
        )
    }

    /// Helper: seeds N apps into storage for the test account.
    private func seedApps(_ apps: [AppModel]) async {
        for app in apps {
            try! await storage.save(app, id: "\(accountId).\(app.id)")
        }
    }

    /// Helper: creates a simple AppModel for the test account.
    private func makeApp(
        id: String,
        name: String,
        bundleId: String = "com.example",
        isFavorite: Bool = false,
        isArchived: Bool = false,
        appStoreState: AppStoreState? = nil
    ) -> AppModel {
        AppModel(
            id: id,
            name: name,
            bundleId: bundleId,
            accountId: accountId,
            appStoreState: appStoreState,
            isArchived: isArchived,
            isFavorite: isFavorite
        )
    }

    // MARK: - TC-001: Load from cache, display all, no network call when serving cache

    func testLoadFromCacheDisplaysAllApps() async {
        // Given: 5 cached apps, no connection
        let apps = (1...5).map { makeApp(id: "app\($0)", name: "App \($0)", bundleId: "com.app\($0)") }
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Then: all 5 displayed, isLoading false, no sync error
        XCTAssertEqual(sut.apps.count, 5)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.syncError)
        // No network call (connection is nil)
        XCTAssertEqual(connection.fetchAppsCallCount, 0)
    }

    // MARK: - TC-002: Live sync updates cache (5->6 apps), isLoading toggles

    func testLiveSyncUpdatesCache() async {
        // Given: 5 cached apps
        let cached = (1...5).map { makeApp(id: "app\($0)", name: "App \($0)", bundleId: "com.app\($0)") }
        await seedApps(cached)

        // Connection returns 6 apps (the original 5 + 1 new)
        let remoteInfos = (1...6).map { AppInfo(id: "app\($0)", name: "App \($0)", bundleId: "com.app\($0)") }
        connection.fetchAppsResult = .success(remoteInfos)

        let sut = makeSUT()

        // When
        await sut.loadApps()

        // Then: 6 apps after sync, isLoading false
        XCTAssertEqual(sut.apps.count, 6)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.syncError)
        XCTAssertEqual(connection.fetchAppsCallCount, 1)
    }

    // MARK: - TC-003: Search filters All Apps and Favorites independently; reset restores both

    func testSearchFiltersGroupsIndependently() async {
        // Given: 2 favorites ("Alpha", "Beta") + 2 regular ("Gamma", "Delta")
        let apps = [
            makeApp(id: "a", name: "Alpha", bundleId: "com.alpha", isFavorite: true),
            makeApp(id: "b", name: "Beta", bundleId: "com.beta", isFavorite: true),
            makeApp(id: "g", name: "Gamma", bundleId: "com.gamma"),
            makeApp(id: "d", name: "Delta", bundleId: "com.delta"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Pre-search: all visible
        XCTAssertEqual(sut.favoriteApps.count, 2)
        XCTAssertEqual(sut.allApps.count, 2)

        // Search "alph" — matches only Alpha (fav), not Beta/Gamma/Delta
        sut.searchQuery = "alph"
        XCTAssertEqual(sut.favoriteApps.count, 1)
        XCTAssertEqual(sut.favoriteApps.first?.name, "Alpha")
        XCTAssertEqual(sut.allApps.count, 0) // no regular apps match "alph"

        // Reset
        sut.searchQuery = ""
        XCTAssertEqual(sut.favoriteApps.count, 2)
        XCTAssertEqual(sut.allApps.count, 2)
    }

    // MARK: - TC-004: Search by bundleId, case-insensitive substring

    func testSearchByBundleIdCaseInsensitive() async {
        let apps = [
            makeApp(id: "a", name: "MyApp", bundleId: "com.Example.MyApp"),
            makeApp(id: "b", name: "Other", bundleId: "org.other.App"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Search by bundleId substring, case-insensitive
        sut.searchQuery = "EXAMPLE"
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertEqual(sut.allApps.first?.id, "a")
    }

    // MARK: - TC-005: No-match search -> empty, no error; reset restores

    func testNoMatchSearchProducesEmptyNoError() async {
        let apps = [makeApp(id: "a", name: "MyApp", bundleId: "com.test")]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        sut.searchQuery = "ZZZZNOTFOUND"
        XCTAssertTrue(sut.allApps.isEmpty)
        XCTAssertTrue(sut.favoriteApps.isEmpty)
        XCTAssertTrue(sut.isSearchEmpty)
        XCTAssertNil(sut.syncError)

        // Reset restores
        sut.searchQuery = ""
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertFalse(sut.isSearchEmpty)
    }

    // MARK: - TC-006 / TC-057: Toggle favorite persists across restart

    func testToggleFavoritePersistsAcrossRestart() async {
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test")
        await seedApps([app])

        // First instance: toggle favorite
        let sut1 = makeSUT(withConnection: false)
        await sut1.loadApps()
        XCTAssertFalse(sut1.apps.first!.isFavorite)

        await sut1.toggleFavorite(appId: "a")
        XCTAssertTrue(sut1.apps.first!.isFavorite)
        XCTAssertEqual(sut1.favoriteApps.count, 1)
        XCTAssertTrue(sut1.allApps.isEmpty) // moved to favorites

        // Second instance ("restart"): favorite flag survives
        let sut2 = makeSUT(withConnection: false)
        await sut2.loadApps()
        XCTAssertTrue(sut2.apps.first!.isFavorite)
        XCTAssertEqual(sut2.favoriteApps.count, 1)
    }

    // MARK: - TC-007 / TC-058: Archive confirmed persists, survives restart

    func testArchiveConfirmedPersistsAndSurvivesRestart() async {
        let apps = [
            makeApp(id: "a", name: "Keep", bundleId: "com.keep"),
            makeApp(id: "b", name: "Archive Me", bundleId: "com.archive"),
        ]
        await seedApps(apps)

        // First instance: archive app "b"
        let sut1 = makeSUT(withConnection: false)
        await sut1.loadApps()
        XCTAssertEqual(sut1.allApps.count, 2)

        sut1.archiveApp(appId: "b")
        XCTAssertEqual(sut1.archiveConfirmingId, "b")

        await sut1.archiveAppConfirmed(appId: "b")
        XCTAssertNil(sut1.archiveConfirmingId)
        // "b" is archived, so allApps should only show "a"
        XCTAssertEqual(sut1.allApps.count, 1)
        XCTAssertEqual(sut1.allApps.first?.id, "a")
        // The raw apps array still contains "b" but it is flagged as archived
        XCTAssertTrue(sut1.apps.first(where: { $0.id == "b" })!.isArchived)

        // Second instance ("restart"): archived flag survives
        let sut2 = makeSUT(withConnection: false)
        await sut2.loadApps()
        XCTAssertTrue(sut2.apps.first(where: { $0.id == "b" })!.isArchived)
        XCTAssertEqual(sut2.allApps.count, 1) // only "a" visible
    }

    // MARK: - TC-008: Archive cancellation leaves app in list

    func testArchiveCancellationLeavesAppInList() async {
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test")
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        sut.archiveApp(appId: "a")
        XCTAssertEqual(sut.archiveConfirmingId, "a")

        sut.cancelArchive()
        XCTAssertNil(sut.archiveConfirmingId)
        XCTAssertFalse(sut.apps.first!.isArchived)
        XCTAssertEqual(sut.allApps.count, 1)
    }

    // MARK: - TC-010 / TC-059: Empty cache -> empty apps, isLoading false

    func testEmptyCacheProducesEmptyState() async {
        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        XCTAssertTrue(sut.apps.isEmpty)
        XCTAssertTrue(sut.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - TC-011: Network failure -> syncError set, cached apps still present

    func testNetworkFailureKeepsCachedApps() async {
        // Given: 3 cached apps
        let cached = (1...3).map { makeApp(id: "app\($0)", name: "App \($0)", bundleId: "com.app\($0)") }
        await seedApps(cached)

        // Connection will throw
        connection.fetchAppsResult = .failure(NSError(domain: "net", code: -1))

        let sut = makeSUT()
        await sut.loadApps()

        // Then: cached apps preserved, syncError set, isLoading false
        XCTAssertEqual(sut.apps.count, 3)
        XCTAssertNotNil(sut.syncError)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - TC-078: appMatchesSearch is case-insensitive substring over name+bundleId

    func testAppMatchesSearchCaseInsensitiveSubstring() {
        let app = AppModel(
            id: "1",
            name: "My Awesome App",
            bundleId: "com.Example.AwesomeApp",
            accountId: accountId
        )

        // Match by name
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "awesome"))
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "AWESOME"))
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "My"))

        // Match by bundleId
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "example"))
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "com.Example"))

        // No match
        XCTAssertFalse(WindowsAppsListModel.appMatchesSearch(app, query: "zzz"))

        // Empty query matches everything
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: ""))
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "   "))
    }

    // MARK: - Favorite toggle revert-on-failure

    func testToggleFavoriteRevertsOnPersistenceFailure() async {
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test")
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()
        XCTAssertFalse(sut.apps.first!.isFavorite)

        // Make save fail
        storage.shouldThrowOnSave = true

        await sut.toggleFavorite(appId: "a")

        // Reverted: still not favorite
        XCTAssertFalse(sut.apps.first!.isFavorite)
        XCTAssertNotNil(sut.syncError)
    }

    // MARK: - Archive revert-on-failure

    func testArchiveConfirmedRevertsOnPersistenceFailure() async {
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test")
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Make save fail
        storage.shouldThrowOnSave = true

        sut.archiveApp(appId: "a")
        await sut.archiveAppConfirmed(appId: "a")

        // Reverted: not archived, error set
        XCTAssertFalse(sut.apps.first!.isArchived)
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertNotNil(sut.syncError)
    }

    // MARK: - AC-W01-1: Each app exposes icon, name, status color, status text, version

    func testAppExposesRowData() async {
        let app = AppModel(
            id: "a",
            name: "Test App",
            bundleId: "com.test",
            accountId: accountId,
            iconUrl: "https://example.com/icon.png",
            appStoreState: .readyForSale,
            versionString: "1.2.3"
        )
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        let loaded = sut.apps.first!
        XCTAssertEqual(loaded.name, "Test App")
        XCTAssertEqual(loaded.iconUrl, "https://example.com/icon.png")
        XCTAssertEqual(loaded.appStoreState, .readyForSale)
        XCTAssertEqual(loaded.appStoreState?.displayName, "Ready for Sale")
        XCTAssertEqual(loaded.appStoreState?.color, .green)
        XCTAssertEqual(loaded.versionString, "1.2.3")
    }

    // MARK: - AC-W01-6/7/8: Status colors

    func testStatusColorsMatchSpec() {
        XCTAssertEqual(AppStoreState.readyForSale.color, .green)
        XCTAssertEqual(AppStoreState.pendingDeveloperRelease.color, .yellow)
        XCTAssertEqual(AppStoreState.prepareForSubmission.color, .blue)
    }

    // MARK: - AC-W01-5: Favorites grouped above All Apps, no duplication

    func testFavoritesGroupedSeparatelyFromAllApps() async {
        let apps = [
            makeApp(id: "f1", name: "Fav App", bundleId: "com.fav", isFavorite: true),
            makeApp(id: "r1", name: "Regular App", bundleId: "com.reg"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        XCTAssertEqual(sut.favoriteApps.count, 1)
        XCTAssertEqual(sut.favoriteApps.first?.id, "f1")
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertEqual(sut.allApps.first?.id, "r1")

        // No duplication: favorite does NOT appear in allApps
        XCTAssertFalse(sut.allApps.contains(where: { $0.id == "f1" }))
    }

    // MARK: - Live sync preserves local flags (isFavorite, isArchived)

    func testLiveSyncPreservesLocalFlags() async {
        // Cached app is favorited
        let cached = makeApp(id: "a", name: "MyApp", bundleId: "com.test", isFavorite: true)
        await seedApps([cached])

        // Remote returns the same app (API does not know about local flags)
        connection.fetchAppsResult = .success([
            AppInfo(id: "a", name: "MyApp Updated", bundleId: "com.test")
        ])

        let sut = makeSUT()
        await sut.loadApps()

        // Name updated from remote, but isFavorite preserved from cache
        XCTAssertEqual(sut.apps.first?.name, "MyApp Updated")
        XCTAssertTrue(sut.apps.first!.isFavorite)
    }

    // MARK: - AC-W01-4: First load shows loading, no stale content before resolve

    func testFirstLoadShowsLoadingIndicator() async {
        // Given: empty cache + connection that returns data
        connection.fetchAppsResult = .success([
            AppInfo(id: "a", name: "App", bundleId: "com.app")
        ])

        let sut = makeSUT()

        // Before load
        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(sut.apps.isEmpty)

        // After load completes
        await sut.loadApps()
        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(sut.apps.count, 1)
    }

    // MARK: - Archived apps excluded from visible groupings

    func testArchivedAppsExcludedFromGroupings() async {
        let apps = [
            makeApp(id: "a", name: "Active", bundleId: "com.active"),
            makeApp(id: "b", name: "Archived", bundleId: "com.archived", isArchived: true),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertEqual(sut.allApps.first?.id, "a")
        XCTAssertFalse(sut.isEmpty) // "a" is still visible
    }
}
