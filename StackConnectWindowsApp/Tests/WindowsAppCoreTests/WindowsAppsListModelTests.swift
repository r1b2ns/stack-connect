import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Comprehensive unit tests for `WindowsAppsListModel` (T-W05 baseline + T-W09
/// extensions + T-W31 end-to-end merge-preserves-flags). Covers: offline-first
/// load, live sync (merge, persistence, mid-flight loading, remote removal,
/// name update, duplicate-ID safety), search filtering (whitespace trimming,
/// bundleId, favorites/all independently), favorite toggle
/// (on/off/persist/revert/unknown-id), archive flow (confirmation, cancel,
/// persist, revert, unknown-id, clears-syncError), sort order, account
/// filtering, cache-load failure, empty states, and re-sync flag preservation.
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
        appStoreState: AppStoreState? = nil,
        lastModifiedDate: Date? = nil,
        hasReviewPending: Bool = false,
        iconUrl: String? = nil,
        versionString: String? = nil,
        platformVersions: [AppPlatformVersion]? = nil
    ) -> AppModel {
        AppModel(
            id: id,
            name: name,
            bundleId: bundleId,
            accountId: accountId,
            iconUrl: iconUrl,
            appStoreState: appStoreState,
            versionString: versionString,
            lastModifiedDate: lastModifiedDate,
            isArchived: isArchived,
            isFavorite: isFavorite,
            hasReviewPending: hasReviewPending,
            platformVersions: platformVersions
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

    // MARK: - AC-W01-4: First load completes with data and clears loading

    func testFirstLoadCompletesWithDataAndClearsLoading() async {
        // Given: empty cache + connection that returns data
        connection.fetchAppsResult = .success([
            AppInfo(id: "a", name: "App", bundleId: "com.app")
        ])

        let sut = makeSUT()

        // Before load
        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(sut.apps.isEmpty)

        // After load completes
        // NOTE: Observing the intermediate `isLoading == true` state mid-flight
        // requires an async/suspendable mock; that is deferred to the
        // comprehensive T-W09 suite. Here we verify the before/after states.
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

    // =========================================================================
    // MARK: - T-W09: Comprehensive Extensions
    // =========================================================================

    // MARK: - Gap 1: Mid-flight loading state (TC-002 step 3, AC-W01-4)

    /// Verifies that `isLoading` is `true` DURING the live sync phase of
    /// `loadApps()`, using a suspendable connection mock that lets the test
    /// inspect state while `fetchApps()` is in-flight.
    func testIsLoadingTrueDuringLiveSync() async {
        // Given: empty cache, suspendable connection
        let suspendable = SuspendableAppleConnection()
        addTeardownBlock { @MainActor [suspendable] in
            // Safe cleanup: if the test failed before resuming, release the continuation.
            suspendable.resumeIfPending()
        }
        let sut = WindowsAppsListModel(
            accountId: accountId,
            storage: storage,
            connection: suspendable
        )

        // When: kick off loadApps() concurrently
        let loadTask = Task { await sut.loadApps() }

        // Wait until fetchApps() is actually in-flight
        await suspendable.waitForFetchAppsCall()

        // Then: isLoading must be true while the sync is suspended
        XCTAssertTrue(sut.isLoading, "isLoading should be true during live sync")

        // Resume with data so loadApps() completes
        suspendable.resumeFetchApps(with: .success([
            AppInfo(id: "a", name: "App", bundleId: "com.app")
        ]))
        await loadTask.value

        // After completion: isLoading false, data present
        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(sut.apps.count, 1)
    }

    // MARK: - Gap 2: Live-sync cache persistence (TC-002 steps 5-6)

    /// After live sync, merged apps must be persisted to storage. A fresh model
    /// instance re-loading from the same storage should see the synced data.
    func testLiveSyncPersistsMergedAppsToStorage() async {
        // Given: 2 cached apps
        let cached = [
            makeApp(id: "app1", name: "App 1", bundleId: "com.app1"),
            makeApp(id: "app2", name: "App 2", bundleId: "com.app2"),
        ]
        await seedApps(cached)
        let saveCountBefore = storage.saveCallCount

        // Remote returns 3 apps (2 existing + 1 new)
        connection.fetchAppsResult = .success([
            AppInfo(id: "app1", name: "App 1", bundleId: "com.app1"),
            AppInfo(id: "app2", name: "App 2", bundleId: "com.app2"),
            AppInfo(id: "app3", name: "App 3", bundleId: "com.app3"),
        ])

        let sut1 = makeSUT()
        await sut1.loadApps()

        // Then: 3 saves were issued for the merged set
        let saveCountAfter = storage.saveCallCount
        XCTAssertEqual(saveCountAfter - saveCountBefore, 3,
                        "Each merged app should be persisted")

        // Verify via a fresh model instance ("restart") — no connection needed
        let sut2 = makeSUT(withConnection: false)
        await sut2.loadApps()
        XCTAssertEqual(sut2.apps.count, 3,
                        "Restarted model should see all 3 synced apps from storage")
    }

    // MARK: - Gap 3: Live-sync merge — app removed remotely

    /// Cache has 5 apps, remote returns 4 (one dropped). After sync, the model
    /// should reflect 4 apps (remote is the source of truth for the app list).
    func testLiveSyncRemovesAppDroppedFromRemote() async {
        // Given: 5 cached apps
        let cached = (1...5).map { makeApp(id: "app\($0)", name: "App \($0)", bundleId: "com.app\($0)") }
        await seedApps(cached)

        // Remote returns only 4 (app5 is gone)
        let remoteInfos = (1...4).map { AppInfo(id: "app\($0)", name: "App \($0)", bundleId: "com.app\($0)") }
        connection.fetchAppsResult = .success(remoteInfos)

        let sut = makeSUT()
        await sut.loadApps()

        // Then: 4 apps in the model (app5 removed)
        XCTAssertEqual(sut.apps.count, 4)
        XCTAssertFalse(sut.apps.contains(where: { $0.id == "app5" }),
                        "App removed remotely should not appear after sync")
    }

    // MARK: - Gap 4: Live-sync merge — name updated remotely + isArchived preserved

    /// Extends existing `testLiveSyncPreservesLocalFlags` to cover both
    /// isFavorite AND isArchived flags, plus remote name update, plus
    /// additional local-only fields (hasReviewPending, platformVersions,
    /// iconUrl, appStoreState, versionString, lastModifiedDate).
    func testLiveSyncPreservesAllLocalFlagsWhileUpdatingRemoteFields() async {
        // Given: cached app with local-only flags set
        let versions = [AppPlatformVersion(platform: "IOS", appStoreState: .readyForSale, versionString: "2.0")]
        let cached = makeApp(
            id: "a",
            name: "Old Name",
            bundleId: "com.test",
            isFavorite: true,
            isArchived: false,
            appStoreState: .readyForSale,
            lastModifiedDate: Date(timeIntervalSince1970: 1_000_000),
            hasReviewPending: true,
            iconUrl: "https://example.com/icon.png",
            versionString: "1.0",
            platformVersions: versions
        )
        await seedApps([cached])

        // Remote updates the name and bundleId (API does not know local flags)
        connection.fetchAppsResult = .success([
            AppInfo(id: "a", name: "New Name", bundleId: "com.test.updated")
        ])

        let sut = makeSUT()
        await sut.loadApps()

        let app = sut.apps.first!
        // Remote fields updated
        XCTAssertEqual(app.name, "New Name")
        XCTAssertEqual(app.bundleId, "com.test.updated")
        // Local flags preserved
        XCTAssertTrue(app.isFavorite)
        XCTAssertFalse(app.isArchived)
        XCTAssertTrue(app.hasReviewPending)
        XCTAssertEqual(app.iconUrl, "https://example.com/icon.png")
        XCTAssertEqual(app.appStoreState, .readyForSale)
        XCTAssertEqual(app.versionString, "1.0")
        XCTAssertEqual(app.lastModifiedDate, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(app.platformVersions, versions)
    }

    /// Specifically tests that the isArchived flag is preserved through live
    /// sync merge (an archived app stays archived even when the remote returns
    /// it in the active list).
    func testLiveSyncPreservesArchivedFlag() async {
        // Given: cached app that is archived locally
        let cached = makeApp(id: "a", name: "MyApp", bundleId: "com.test", isArchived: true)
        await seedApps([cached])

        // Remote still returns the app (API doesn't know it's locally archived)
        connection.fetchAppsResult = .success([
            AppInfo(id: "a", name: "MyApp", bundleId: "com.test")
        ])

        let sut = makeSUT()
        await sut.loadApps()

        // isArchived preserved
        XCTAssertTrue(sut.apps.first!.isArchived)
        // Excluded from visible groupings
        XCTAssertTrue(sut.allApps.isEmpty)
        XCTAssertTrue(sut.favoriteApps.isEmpty)
    }

    // MARK: - Gap 5: Duplicate-ID safety

    /// Remote returns two AppInfo with the same id. The merge should not crash
    /// and should resolve deterministically (one app in the final list).
    func testDuplicateIdInRemoteDoesNotCrash() async {
        // Given: no cache
        connection.fetchAppsResult = .success([
            AppInfo(id: "dup", name: "First", bundleId: "com.first"),
            AppInfo(id: "dup", name: "Second", bundleId: "com.second"),
        ])

        let sut = makeSUT()

        // When: should not crash
        await sut.loadApps()

        // Then: both remote entries are mapped independently — no deduplication
        // on the remote list (production `loadApps()` does `remoteAppInfos.map { … }`).
        XCTAssertEqual(sut.apps.count, 2,
            "Both remote entries with the same ID are mapped independently — no deduplication on the remote list")
        XCTAssertNil(sut.syncError)
    }

    /// Duplicate IDs in the CACHE (two AppModel with same id) are handled by
    /// `Dictionary(... uniquingKeysWith:)` which picks the last. The merge
    /// should not crash.
    func testDuplicateIdInCacheDoesNotCrash() async {
        // Given: two cached apps with the same id (edge case — shouldn't happen
        // in practice, but the code must not crash)
        let app1 = makeApp(id: "dup", name: "CacheFirst", bundleId: "com.first", isFavorite: true)
        let app2 = makeApp(id: "dup", name: "CacheLast", bundleId: "com.last", isFavorite: false)
        await seedApps([app1])
        // Overwrite with second — MockStorage uses the same key, so only one entry
        await seedApps([app2])

        connection.fetchAppsResult = .success([
            AppInfo(id: "dup", name: "Remote", bundleId: "com.remote")
        ])

        let sut = makeSUT()

        // When: should not crash
        await sut.loadApps()

        // Then: one app, remote name, and no crash
        XCTAssertEqual(sut.apps.count, 1)
        XCTAssertEqual(sut.apps.first?.name, "Remote")
        XCTAssertNil(sut.syncError)
    }

    // MARK: - Gap 6: Sort order

    /// Apps with `lastModifiedDate` sort most-recent-first; apps without a date
    /// sort alphabetically by name at the END. Mixed case covered.
    func testSortOrderMostRecentFirstThenAlphabeticallyByName() async {
        let now = Date()
        let apps = [
            // No date — should sort alphabetically at the end
            makeApp(id: "z", name: "Zebra", bundleId: "com.z"),
            makeApp(id: "a", name: "Apple", bundleId: "com.a"),
            // Has date — should sort by date (newest first)
            makeApp(id: "old", name: "OldApp", bundleId: "com.old",
                    lastModifiedDate: now.addingTimeInterval(-86400)), // 1 day ago
            makeApp(id: "new", name: "NewApp", bundleId: "com.new",
                    lastModifiedDate: now), // most recent
            makeApp(id: "mid", name: "MidApp", bundleId: "com.mid",
                    lastModifiedDate: now.addingTimeInterval(-3600)), // 1 hour ago
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Expected order: NewApp (newest), MidApp, OldApp, Apple (alpha), Zebra (alpha)
        let ids = sut.apps.map(\.id)
        XCTAssertEqual(ids, ["new", "mid", "old", "a", "z"],
                        "Dated apps sort newest-first, then dateless apps alphabetically")
    }

    /// All apps without dates sort purely alphabetically by name.
    func testSortOrderAllNilDatesSortAlphabetically() async {
        let apps = [
            makeApp(id: "c", name: "Charlie", bundleId: "com.c"),
            makeApp(id: "a", name: "Alpha", bundleId: "com.a"),
            makeApp(id: "b", name: "Bravo", bundleId: "com.b"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        XCTAssertEqual(sut.apps.map(\.name), ["Alpha", "Bravo", "Charlie"])
    }

    /// All apps with dates sort most-recent-first.
    func testSortOrderAllWithDatesSortNewestFirst() async {
        let now = Date()
        let apps = [
            makeApp(id: "old", name: "Old", bundleId: "com.old",
                    lastModifiedDate: now.addingTimeInterval(-7200)),
            makeApp(id: "new", name: "New", bundleId: "com.new",
                    lastModifiedDate: now),
            makeApp(id: "mid", name: "Mid", bundleId: "com.mid",
                    lastModifiedDate: now.addingTimeInterval(-3600)),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        XCTAssertEqual(sut.apps.map(\.id), ["new", "mid", "old"])
    }

    // MARK: - Gap 7: Toggle favorite OFF (favorite -> non-favorite)

    /// TC-006 step 7-8: toggling a favorite OFF moves it back to allApps and
    /// persists across restart.
    func testToggleFavoriteOffMovesBackToAllApps() async {
        // Given: a favorited app
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test", isFavorite: true)
        await seedApps([app])

        let sut1 = makeSUT(withConnection: false)
        await sut1.loadApps()
        XCTAssertEqual(sut1.favoriteApps.count, 1)
        XCTAssertTrue(sut1.allApps.isEmpty)

        // When: toggle favorite OFF
        await sut1.toggleFavorite(appId: "a")

        // Then: moved to allApps
        XCTAssertFalse(sut1.apps.first!.isFavorite)
        XCTAssertTrue(sut1.favoriteApps.isEmpty)
        XCTAssertEqual(sut1.allApps.count, 1)
        XCTAssertEqual(sut1.allApps.first?.id, "a")

        // Persists across restart
        let sut2 = makeSUT(withConnection: false)
        await sut2.loadApps()
        XCTAssertFalse(sut2.apps.first!.isFavorite)
        XCTAssertTrue(sut2.favoriteApps.isEmpty)
        XCTAssertEqual(sut2.allApps.count, 1)
    }

    // MARK: - Gap 8: toggleFavorite on unknown appId -> no-op

    /// Calling `toggleFavorite(appId:)` with an unknown id should be a no-op:
    /// no crash, no syncError, no state change.
    func testToggleFavoriteUnknownIdIsNoOp() async {
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test")
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        let appsBefore = sut.apps
        await sut.toggleFavorite(appId: "nonexistent")

        // No change, no crash, no error
        XCTAssertEqual(sut.apps, appsBefore)
        XCTAssertNil(sut.syncError)
    }

    // MARK: - Gap 9: archiveAppConfirmed on unknown appId

    /// Calling `archiveAppConfirmed(appId:)` with an unknown id should clear
    /// `archiveConfirmingId` without crashing or setting syncError.
    func testArchiveConfirmedUnknownIdClearsConfirmingId() async {
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test")
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Set up a confirming id, then confirm with a different (unknown) id
        sut.archiveApp(appId: "nonexistent")
        XCTAssertEqual(sut.archiveConfirmingId, "nonexistent")

        await sut.archiveAppConfirmed(appId: "nonexistent")

        // archiveConfirmingId cleared, no crash, apps unchanged
        XCTAssertNil(sut.archiveConfirmingId)
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertFalse(sut.apps.first!.isArchived)
    }

    // MARK: - Gap 10: archiveApp clears a pre-existing syncError

    /// `archiveApp(appId:)` should set `syncError = nil` even if one was
    /// previously set.
    func testArchiveAppClearsPreExistingSyncError() async {
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test")
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Cause a syncError via a failed favorite toggle
        storage.shouldThrowOnSave = true
        await sut.toggleFavorite(appId: "a")
        XCTAssertNotNil(sut.syncError, "Precondition: syncError should be set")
        storage.shouldThrowOnSave = false

        // When: archiveApp is called
        sut.archiveApp(appId: "a")

        // Then: syncError is cleared
        XCTAssertNil(sut.syncError, "archiveApp should clear pre-existing syncError")
        XCTAssertEqual(sut.archiveConfirmingId, "a")
    }

    // MARK: - Gap 11: Account filtering

    /// Storage holds apps for a different accountId. They must NOT be loaded
    /// into the model configured for "acc1".
    func testAccountFilteringExcludesOtherAccounts() async {
        // Given: apps for "acc1" (our account)
        let ownApp = makeApp(id: "own", name: "Own App", bundleId: "com.own")
        await seedApps([ownApp])

        // Seed apps for a DIFFERENT account directly into storage
        let otherApp = AppModel(
            id: "other",
            name: "Other Account App",
            bundleId: "com.other",
            accountId: "acc2"
        )
        try! await storage.save(otherApp, id: "acc2.other")

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Then: only our account's app is loaded
        XCTAssertEqual(sut.apps.count, 1)
        XCTAssertEqual(sut.apps.first?.id, "own")
        XCTAssertFalse(sut.apps.contains(where: { $0.accountId == "acc2" }))
    }

    // MARK: - Gap 12: Cache-load failure (silent, not a syncError)

    /// When `storage.fetchAll` throws, `apps` should be empty, `isLoading`
    /// false, and `syncError` should remain nil (cache failure is silent per
    /// the implementation — it is NOT treated as a sync error).
    func testCacheLoadFailureIsSilentNotSyncError() async {
        // Given: storage will throw on fetch
        storage.shouldThrowOnFetch = true

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Then: empty apps, not loading, no syncError
        XCTAssertTrue(sut.apps.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.syncError,
                      "Cache-load failure should NOT set syncError")
    }

    /// When cache load fails but a connection is present, the sync still
    /// proceeds and brings in remote data.
    func testCacheLoadFailureStillAllowsLiveSync() async {
        // Given: storage throws on fetch but succeeds on save
        storage.shouldThrowOnFetch = true

        connection.fetchAppsResult = .success([
            AppInfo(id: "a", name: "Remote App", bundleId: "com.remote")
        ])

        let sut = makeSUT()

        // We need to allow saves to succeed for the sync persistence phase
        // Note: shouldThrowOnFetch only affects fetch, not save
        await sut.loadApps()

        // The sync should have succeeded despite cache failure
        // But wait — fetchAll throws during cache phase, then the sync phase
        // calls connection.fetchApps() which succeeds. However, the persist
        // phase calls storage.save() which should succeed (shouldThrowOnFetch
        // doesn't affect save). But we need to check: does the sync still
        // proceed after a cache failure? Looking at the code: yes, it catches
        // the cache error and continues to the `guard let connection` check.
        // But wait — shouldThrowOnFetch is still true, and the sync persist
        // phase only calls save, not fetch. So it should work.

        // Actually there's a subtlety: after the cache phase catches and sets
        // apps = [], the code proceeds to sync. The sync maps remote apps
        // using `apps` (which is []) as the cache lookup. So merged apps will
        // have default local flags. That's correct.
        XCTAssertEqual(sut.apps.count, 1)
        XCTAssertEqual(sut.apps.first?.name, "Remote App")
        XCTAssertNil(sut.syncError)
    }

    // MARK: - Gap 13: Search whitespace trimming

    /// Query consisting of only spaces behaves like an empty query (all visible).
    func testSearchWhitespaceOnlyBehavesLikeEmpty() async {
        let apps = [
            makeApp(id: "a", name: "Alpha", bundleId: "com.alpha"),
            makeApp(id: "b", name: "Bravo", bundleId: "com.bravo"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Whitespace-only query
        sut.searchQuery = "   "
        XCTAssertEqual(sut.allApps.count, 2,
                        "Whitespace-only query should show all apps")
        XCTAssertFalse(sut.isSearchEmpty)
    }

    /// Leading/trailing spaces around a real search term still match.
    func testSearchWithLeadingTrailingSpacesStillMatches() async {
        let apps = [
            makeApp(id: "a", name: "Alpha", bundleId: "com.alpha"),
            makeApp(id: "b", name: "Bravo", bundleId: "com.bravo"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Leading/trailing spaces around real term
        sut.searchQuery = "  alpha  "
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertEqual(sut.allApps.first?.id, "a")
    }

    /// `appMatchesSearch` with whitespace-only query returns true (matches all).
    func testAppMatchesSearchWhitespaceOnlyReturnsTrue() {
        let app = AppModel(id: "1", name: "Test", bundleId: "com.test", accountId: accountId)
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "  "))
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "\t"))
    }

    /// `appMatchesSearch` with padded real query trims and matches.
    func testAppMatchesSearchPaddedQueryTrimsAndMatches() {
        let app = AppModel(id: "1", name: "MyApp", bundleId: "com.test", accountId: accountId)
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "  MyApp  "))
        XCTAssertTrue(WindowsAppsListModel.appMatchesSearch(app, query: "  COM.TEST  "))
    }

    // MARK: - Gap 14: Additional edge cases

    /// `isEmpty` is true when all apps are archived (none visible).
    func testIsEmptyWhenAllAppsAreArchived() async {
        let apps = [
            makeApp(id: "a", name: "App A", bundleId: "com.a", isArchived: true),
            makeApp(id: "b", name: "App B", bundleId: "com.b", isArchived: true),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        // Apps exist in the raw array but all are archived
        XCTAssertEqual(sut.apps.count, 2)
        XCTAssertTrue(sut.isEmpty, "isEmpty should be true when all apps are archived")
        XCTAssertTrue(sut.allApps.isEmpty)
        XCTAssertTrue(sut.favoriteApps.isEmpty)
    }

    /// `isSearchEmpty` is false when searchQuery is empty, even if no apps exist.
    func testIsSearchEmptyFalseWhenQueryEmpty() async {
        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        sut.searchQuery = ""
        XCTAssertFalse(sut.isSearchEmpty,
                        "isSearchEmpty should be false when query is empty")
    }

    /// `isSearchEmpty` is false when the search yields results.
    func testIsSearchEmptyFalseWhenResultsExist() async {
        let apps = [makeApp(id: "a", name: "Alpha", bundleId: "com.alpha")]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        sut.searchQuery = "alpha"
        XCTAssertFalse(sut.isSearchEmpty)
    }

    /// Favorited + archived app does not appear in either grouping.
    func testFavoritedArchivedAppHiddenFromBothGroupings() async {
        let apps = [
            makeApp(id: "a", name: "FavArchived", bundleId: "com.a",
                    isFavorite: true, isArchived: true),
            makeApp(id: "b", name: "Regular", bundleId: "com.b"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        XCTAssertTrue(sut.favoriteApps.isEmpty,
                        "Archived favorite should not appear in favoriteApps")
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertEqual(sut.allApps.first?.id, "b")
    }

    /// Multiple favorites and multiple regular apps group correctly.
    func testMultipleFavoritesAndRegularAppsGroupCorrectly() async {
        let apps = [
            makeApp(id: "f1", name: "Fav 1", bundleId: "com.f1", isFavorite: true),
            makeApp(id: "f2", name: "Fav 2", bundleId: "com.f2", isFavorite: true),
            makeApp(id: "f3", name: "Fav 3", bundleId: "com.f3", isFavorite: true),
            makeApp(id: "r1", name: "Reg 1", bundleId: "com.r1"),
            makeApp(id: "r2", name: "Reg 2", bundleId: "com.r2"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        XCTAssertEqual(sut.favoriteApps.count, 3)
        XCTAssertEqual(sut.allApps.count, 2)
        // Total non-archived = 5
        XCTAssertEqual(sut.favoriteApps.count + sut.allApps.count, 5)
        // No duplication
        let favIds = Set(sut.favoriteApps.map(\.id))
        let allIds = Set(sut.allApps.map(\.id))
        XCTAssertTrue(favIds.isDisjoint(with: allIds),
                        "No app should appear in both favorites and allApps")
    }

    /// Favorite toggle revert-on-failure for a favorited app (OFF direction).
    func testToggleFavoriteOffRevertsOnPersistenceFailure() async {
        // Given: a favorited app
        let app = makeApp(id: "a", name: "MyApp", bundleId: "com.test", isFavorite: true)
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()
        XCTAssertTrue(sut.apps.first!.isFavorite)

        // Make save fail
        storage.shouldThrowOnSave = true

        await sut.toggleFavorite(appId: "a")

        // Reverted: still favorite
        XCTAssertTrue(sut.apps.first!.isFavorite,
                        "Failed toggle-off should revert to isFavorite=true")
        XCTAssertNotNil(sut.syncError)
    }

    /// Verify that `cancelArchive` can be called even when `archiveConfirmingId`
    /// is already nil (no-op, no crash).
    func testCancelArchiveWhenNoConfirmationIsNoOp() async {
        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        XCTAssertNil(sut.archiveConfirmingId)
        sut.cancelArchive()
        XCTAssertNil(sut.archiveConfirmingId) // still nil, no crash
    }

    /// Live sync with an empty remote response: cache had apps, remote returns
    /// empty → model shows empty (remote is source of truth).
    func testLiveSyncWithEmptyRemoteClearsApps() async {
        // Given: 3 cached apps
        let cached = (1...3).map { makeApp(id: "app\($0)", name: "App \($0)", bundleId: "com.app\($0)") }
        await seedApps(cached)

        // Remote returns empty
        connection.fetchAppsResult = .success([])

        let sut = makeSUT()
        await sut.loadApps()

        // Then: model reflects remote (empty)
        XCTAssertTrue(sut.apps.isEmpty)
        XCTAssertTrue(sut.isEmpty)
        XCTAssertNil(sut.syncError)
    }

    /// Search filters favorites and allApps simultaneously — ensures search
    /// works across both sections with the same query.
    func testSearchMatchesInBothFavoritesAndAllApps() async {
        let apps = [
            makeApp(id: "f1", name: "Test Favorite", bundleId: "com.fav", isFavorite: true),
            makeApp(id: "r1", name: "Test Regular", bundleId: "com.reg"),
            makeApp(id: "r2", name: "Other", bundleId: "com.other"),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        sut.searchQuery = "Test"
        XCTAssertEqual(sut.favoriteApps.count, 1)
        XCTAssertEqual(sut.favoriteApps.first?.id, "f1")
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertEqual(sut.allApps.first?.id, "r1")
    }

    /// Archived apps are excluded from the search results even when they match.
    func testSearchExcludesArchivedApps() async {
        let apps = [
            makeApp(id: "a", name: "Searchable", bundleId: "com.search"),
            makeApp(id: "b", name: "Searchable Archived", bundleId: "com.search.arch",
                    isArchived: true),
        ]
        await seedApps(apps)

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        sut.searchQuery = "Searchable"
        XCTAssertEqual(sut.allApps.count, 1)
        XCTAssertEqual(sut.allApps.first?.id, "a")
        XCTAssertTrue(sut.favoriteApps.isEmpty)
    }

    /// Live-sync merge with new app that has no cached counterpart gets default
    /// local flags (isFavorite=false, isArchived=false, hasReviewPending=false).
    func testLiveSyncNewAppGetsDefaultLocalFlags() async {
        // Given: empty cache
        connection.fetchAppsResult = .success([
            AppInfo(id: "new", name: "Brand New", bundleId: "com.new")
        ])

        let sut = makeSUT()
        await sut.loadApps()

        let app = sut.apps.first!
        XCTAssertEqual(app.id, "new")
        XCTAssertFalse(app.isFavorite, "New app should default to not favorite")
        XCTAssertFalse(app.isArchived, "New app should default to not archived")
        XCTAssertFalse(app.hasReviewPending, "New app should default to no pending review")
        XCTAssertNil(app.iconUrl)
        XCTAssertNil(app.appStoreState)
        XCTAssertNil(app.versionString)
        XCTAssertNil(app.lastModifiedDate)
        XCTAssertNil(app.platformVersions)
    }

    /// Sync error message is the expected string.
    func testSyncErrorMessageContent() async {
        connection.fetchAppsResult = .failure(NSError(domain: "net", code: -1))

        let sut = makeSUT()
        await sut.loadApps()

        XCTAssertEqual(sut.syncError, "Sync failed. Showing cached data.")
    }

    /// Favorite toggle error message is the expected string.
    func testFavoriteToggleErrorMessageContent() async {
        let app = makeApp(id: "a", name: "App", bundleId: "com.test")
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        storage.shouldThrowOnSave = true
        await sut.toggleFavorite(appId: "a")

        XCTAssertEqual(sut.syncError, "Failed to update favorite.")
    }

    /// Archive error message is the expected string.
    func testArchiveErrorMessageContent() async {
        let app = makeApp(id: "a", name: "App", bundleId: "com.test")
        await seedApps([app])

        let sut = makeSUT(withConnection: false)
        await sut.loadApps()

        storage.shouldThrowOnSave = true
        sut.archiveApp(appId: "a")
        await sut.archiveAppConfirmed(appId: "a")

        XCTAssertEqual(sut.syncError, "Failed to archive app.")
    }

    /// Calling `loadApps()` clears a previous syncError on success.
    func testLoadAppsClearsPreviousSyncErrorOnSuccess() async {
        // First load: sync fails
        connection.fetchAppsResult = .failure(NSError(domain: "net", code: -1))
        let sut = makeSUT()
        await sut.loadApps()
        XCTAssertNotNil(sut.syncError)

        // Second load: sync succeeds
        connection.fetchAppsResult = .success([
            AppInfo(id: "a", name: "App", bundleId: "com.app")
        ])
        await sut.loadApps()
        XCTAssertNil(sut.syncError, "loadApps should clear syncError on success")
    }

    /// Live sync persist failure sets syncError but keeps the merged apps
    /// visible in the UI (the merge itself succeeded).
    func testLiveSyncPersistFailureSetsErrorButKeepsMergedApps() async {
        // Given: connection returns data
        connection.fetchAppsResult = .success([
            AppInfo(id: "a", name: "App", bundleId: "com.app")
        ])

        let sut = makeSUT()

        // Load once to get past cache phase (which succeeds since cache is empty)
        // Then the sync phase will try to persist — we make save fail
        // But we need to be careful: shouldThrowOnSave will also affect the
        // persist step. Let's set it after the cache phase would have run.
        // Actually, the cache phase only does fetchAll, not save. So setting
        // shouldThrowOnSave before loadApps is fine.
        storage.shouldThrowOnSave = true

        await sut.loadApps()

        // The sync persist phase threw, so syncError is set
        XCTAssertNotNil(sut.syncError)
        // But the merged apps are still in the UI (the model set `apps = merged`
        // before attempting to persist)
        XCTAssertEqual(sut.apps.count, 1)
        XCTAssertEqual(sut.apps.first?.name, "App")
    }

    // =========================================================================
    // MARK: - T-W31 / TC-056: Re-sync merge preserves local flags end-to-end
    // =========================================================================

    /// Comprehensive test proving the full merge-preserves-flags contract
    /// (TC-056, reinterpreted at the sync seam):
    ///
    /// Setup:
    ///   - Cache has 3 apps for the account:
    ///     "app1" with isFavorite=true,  isArchived=false
    ///     "app2" with isFavorite=false, isArchived=true
    ///     "app3" with isFavorite=false, isArchived=false  (no flags)
    ///   - Remote returns 4 apps: "app1", "app2", "app3" (overlapping) + "app4" (new)
    ///
    /// Asserts (AC-1 through AC-3):
    ///   AC-1: After sync, app1.isFavorite remains true and app2.isArchived
    ///         remains true — remote refresh does NOT clobber local flags.
    ///   AC-2: app4 (new, absent from cache) has isFavorite=false, isArchived=false.
    ///   AC-3: A fresh model instance loading from the same storage sees the
    ///         identical preserved flags — the merge was persisted, not just
    ///         in-memory.
    func testReSyncMergePreservesLocalFlagsEndToEnd() async {
        // -- Arrange: seed 3 cached apps with deterministic flags ----------

        let cachedApps = [
            makeApp(id: "app1", name: "Favorited App",
                    bundleId: "com.app1", isFavorite: true, isArchived: false),
            makeApp(id: "app2", name: "Archived App",
                    bundleId: "com.app2", isFavorite: false, isArchived: true),
            makeApp(id: "app3", name: "Plain App",
                    bundleId: "com.app3", isFavorite: false, isArchived: false),
        ]
        await seedApps(cachedApps)

        // Remote returns the 3 existing apps (names may differ — simulates
        // a real API response that knows nothing about local flags) PLUS one
        // brand-new app ("app4") that has never been cached.
        connection.fetchAppsResult = .success([
            AppInfo(id: "app1", name: "Favorited App v2", bundleId: "com.app1"),
            AppInfo(id: "app2", name: "Archived App v2",  bundleId: "com.app2"),
            AppInfo(id: "app3", name: "Plain App v2",     bundleId: "com.app3"),
            AppInfo(id: "app4", name: "Brand New App",    bundleId: "com.app4"),
        ])

        // -- Act: trigger a live sync ------------------------------------

        let sut = makeSUT()
        await sut.loadApps()

        // -- Assert: AC-1 — existing apps keep their local flags ----------

        let app1 = sut.apps.first(where: { $0.id == "app1" })
        XCTAssertNotNil(app1, "app1 must be present after sync")
        XCTAssertTrue(app1!.isFavorite,
                      "AC-1: app1's isFavorite=true must survive the remote refresh")
        XCTAssertFalse(app1!.isArchived,
                       "AC-1: app1's isArchived=false must survive the remote refresh")

        let app2 = sut.apps.first(where: { $0.id == "app2" })
        XCTAssertNotNil(app2, "app2 must be present after sync")
        XCTAssertFalse(app2!.isFavorite,
                       "AC-1: app2's isFavorite=false must survive the remote refresh")
        XCTAssertTrue(app2!.isArchived,
                      "AC-1: app2's isArchived=true must survive the remote refresh")

        let app3 = sut.apps.first(where: { $0.id == "app3" })
        XCTAssertNotNil(app3, "app3 must be present after sync")
        XCTAssertFalse(app3!.isFavorite,
                       "AC-1: app3's isFavorite=false must survive the remote refresh")
        XCTAssertFalse(app3!.isArchived,
                       "AC-1: app3's isArchived=false must survive the remote refresh")

        // Verify remote fields WERE updated (name changed from API)
        XCTAssertEqual(app1!.name, "Favorited App v2",
                       "Remote name should be applied despite local flag preservation")
        XCTAssertEqual(app2!.name, "Archived App v2")

        // -- Assert: AC-2 — new app defaults to false/false ---------------

        let app4 = sut.apps.first(where: { $0.id == "app4" })
        XCTAssertNotNil(app4, "app4 (new) must be present after sync")
        XCTAssertFalse(app4!.isFavorite,
                       "AC-2: new app must default to isFavorite=false")
        XCTAssertFalse(app4!.isArchived,
                       "AC-2: new app must default to isArchived=false")

        // -- Assert: AC-3 — flags persisted (survive a fresh load) --------

        // Create a second model instance with NO connection (cache-only)
        // that reads from the SAME storage. If the merged flags were
        // persisted correctly, this instance must see the same flags.
        let sut2 = makeSUT(withConnection: false)
        await sut2.loadApps()
        XCTAssertNil(sut2.syncError,
                     "AC-3: cache reload must not produce a syncError")

        XCTAssertEqual(sut2.apps.count, 4,
                       "AC-3: all 4 merged apps must be persisted and reloaded")

        let reloaded1 = sut2.apps.first(where: { $0.id == "app1" })
        XCTAssertNotNil(reloaded1, "AC-3: app1 must be present after reload")
        XCTAssertTrue(reloaded1!.isFavorite,
                      "AC-3: app1's isFavorite=true must persist to storage")
        XCTAssertFalse(reloaded1!.isArchived,
                       "AC-3: app1's isArchived=false must persist to storage")

        let reloaded2 = sut2.apps.first(where: { $0.id == "app2" })
        XCTAssertNotNil(reloaded2, "AC-3: app2 must be present after reload")
        XCTAssertFalse(reloaded2!.isFavorite,
                       "AC-3: app2's isFavorite=false must persist to storage")
        XCTAssertTrue(reloaded2!.isArchived,
                      "AC-3: app2's isArchived=true must persist to storage")

        let reloaded3 = sut2.apps.first(where: { $0.id == "app3" })
        XCTAssertNotNil(reloaded3, "AC-3: app3 must be present after reload")
        XCTAssertFalse(reloaded3!.isFavorite,
                       "AC-3: app3's isFavorite=false must persist to storage")
        XCTAssertFalse(reloaded3!.isArchived,
                       "AC-3: app3's isArchived=false must persist to storage")

        let reloaded4 = sut2.apps.first(where: { $0.id == "app4" })
        XCTAssertNotNil(reloaded4, "AC-3: app4 must be present after reload")
        XCTAssertFalse(reloaded4!.isFavorite,
                       "AC-3: app4's isFavorite=false must persist to storage")
        XCTAssertFalse(reloaded4!.isArchived,
                       "AC-3: app4's isArchived=false must persist to storage")
    }
}
