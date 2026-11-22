import XCTest
import StackProtocols
@testable import StackConnect

/// Favorite / archive on the Google Play app list (mirrors the App Store
/// `AppListViewModel`): sections, persistence, sync merge, analytics and the
/// widget refresh. Locale-independent: copy is compared through
/// `String(localized:)`, never as literal English.
@MainActor
final class GooglePlayAppListFavoriteArchiveTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayAccountConnection!
    private var analytics: MockAnalyticsTracker!
    private var defaultsSuiteName: String!
    private var dashboardRefreshes = 0

    private let account = AccountModel(name: "Play Team", providerType: .googlePlay)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayAccountConnection()
        analytics = MockAnalyticsTracker()
        dashboardRefreshes = 0
        defaultsSuiteName = "GooglePlayAppListFavoriteArchiveTests.\(UUID().uuidString)"
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        analytics = nil
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT() -> GooglePlayAppListViewModel {
        GooglePlayAppListViewModel(
            account: account,
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.appListFactory,
            accessCheckerFactory: { _ in MockGooglePlayAppAccessChecker() },
            connectivity: MockConnectivityProviding(online: true),
            analytics: analytics,
            firstAppsLoaded: FirstAppsLoadedTracker(
                defaults: UserDefaults(suiteName: defaultsSuiteName) ?? .standard,
                analytics: analytics
            ),
            dashboardDidChange: { [weak self] _ in self?.dashboardRefreshes += 1 }
        )
    }

    private func seedCache(_ apps: [GooglePlayAppItem]) async throws {
        try await storage.save(apps, id: GooglePlayAppItem.cacheKey(accountId: account.id))
    }

    private func cachedApps() async throws -> [GooglePlayAppItem]? {
        try await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: account.id))
    }

    /// A loaded SUT whose API returns the cached apps unchanged.
    private func loadedSUT(_ items: [GooglePlayAppItem]) async throws -> GooglePlayAppListViewModel {
        try await seedCache(items)
        let remote = items.filter { !$0.isManuallyAdded }.map { playApp($0.packageName, name: $0.title ?? $0.packageName) }
        connection.fetchAppsHandler = { remote }
        let sut = makeSUT()
        await sut.load()
        return sut
    }

    // MARK: - UiState sections

    func testFavoritesComeFirstAndArchivedAppsAreHidden() {
        var state = GooglePlayAppListUiState(account: account)
        state.apps = [
            item("com.a", title: "Alpha"),
            item("com.b", title: "Bravo", favorite: true),
            item("com.c", title: "Charlie", archived: true),
            item("com.d", title: "Delta", favorite: true, archived: true)
        ]

        XCTAssertEqual(state.visibleApps.map(\.packageName), ["com.a", "com.b"])
        XCTAssertEqual(state.filteredApps.map(\.packageName), ["com.a", "com.b"])
        XCTAssertEqual(state.favoriteApps.map(\.packageName), ["com.b"])
        XCTAssertEqual(state.regularApps.map(\.packageName), ["com.a"])
    }

    func testSearchNeverMatchesArchivedApps() {
        var state = GooglePlayAppListUiState(account: account)
        state.apps = [item("com.match.live", title: "Live"), item("com.match.archived", title: "Gone", archived: true)]
        state.searchQuery = "match"

        XCTAssertEqual(state.filteredApps.map(\.packageName), ["com.match.live"])
    }

    // MARK: - Favorite

    func testToggleFavoritePersistsTracksAndToasts() async throws {
        let sut = try await loadedSUT([item("com.a", title: "Alpha"), item("com.b", title: "Bravo")])
        let app = try XCTUnwrap(sut.uiState.apps.first { $0.packageName == "com.b" })

        await sut.toggleFavorite(app: app)

        XCTAssertEqual(sut.uiState.favoriteApps.map(\.packageName), ["com.b"])
        let cached = try await cachedApps()
        XCTAssertEqual(cached?.first { $0.packageName == "com.b" }?.isFavorite, true)
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Added to favorites"))
        XCTAssertEqual(analytics.taps(of: .favorite), [.buttonTap(.favorite, on: .googlePlayAppList)])
        XCTAssertEqual(analytics.actions(of: .toggleFavorite), [
            .action(.toggleFavorite, on: .googlePlayAppList, result: .success, parameters: [AnalyticsParameterKey.enabled: .bool(true)])
        ])
        XCTAssertEqual(dashboardRefreshes, 0, "Favorites don't change the widgets")
    }

    func testToggleFavoriteTwiceUnfavorites() async throws {
        let sut = try await loadedSUT([item("com.a", title: "Alpha", favorite: true)])
        let app = try XCTUnwrap(sut.uiState.apps.first)

        await sut.toggleFavorite(app: app)

        XCTAssertTrue(sut.uiState.favoriteApps.isEmpty)
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Removed from favorites"))
        let cached = try await cachedApps()
        XCTAssertEqual(cached?.first?.isFavorite, false)
    }

    func testToggleFavoriteRevertsWhenTheSaveFails() async throws {
        let sut = try await loadedSUT([item("com.a", title: "Alpha")])
        let app = try XCTUnwrap(sut.uiState.apps.first)
        await storage.failSave([GooglePlayAppItem].self)

        await sut.toggleFavorite(app: app)

        XCTAssertEqual(sut.uiState.apps.first?.isFavorite, false)
        XCTAssertNil(sut.uiState.toastMessage)
        XCTAssertEqual(analytics.results(of: .toggleFavorite), [.failure])
    }

    // MARK: - Archive

    func testToggleArchiveHidesTheAppPersistsAndRefreshesTheWidgets() async throws {
        let sut = try await loadedSUT([item("com.a", title: "Alpha"), item("com.b", title: "Bravo")])
        let app = try XCTUnwrap(sut.uiState.apps.first { $0.packageName == "com.a" })

        await sut.toggleArchive(app: app)

        XCTAssertEqual(sut.uiState.filteredApps.map(\.packageName), ["com.b"])
        XCTAssertEqual(sut.uiState.apps.count, 2, "Archived apps stay in the list's data")
        let cached = try await cachedApps()
        XCTAssertEqual(cached?.first { $0.packageName == "com.a" }?.isArchived, true)
        XCTAssertEqual(dashboardRefreshes, 1)
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "App archived"))
        XCTAssertEqual(analytics.taps(of: .archive), [.buttonTap(.archive, on: .googlePlayAppList)])
        XCTAssertEqual(analytics.actions(of: .toggleArchive), [
            .action(.toggleArchive, on: .googlePlayAppList, result: .success, parameters: [AnalyticsParameterKey.enabled: .bool(true)])
        ])
    }

    func testToggleArchiveRevertsWhenTheSaveFails() async throws {
        let sut = try await loadedSUT([item("com.a", title: "Alpha")])
        let app = try XCTUnwrap(sut.uiState.apps.first)
        await storage.failSave([GooglePlayAppItem].self)

        await sut.toggleArchive(app: app)

        XCTAssertEqual(sut.uiState.filteredApps.map(\.packageName), ["com.a"])
        XCTAssertEqual(dashboardRefreshes, 0)
        XCTAssertEqual(analytics.results(of: .toggleArchive), [.failure])
    }

    func testToggleOfAnUnknownAppDoesNothingButTheTap() async {
        let sut = makeSUT()

        await sut.toggleArchive(app: item("com.unknown"))

        XCTAssertEqual(analytics.taps(of: .archive).count, 1)
        XCTAssertTrue(analytics.actions(of: .toggleArchive).isEmpty)
    }

    // MARK: - Sync keeps the flags

    func testSyncKeepsFavoriteAndArchivedFlags() async throws {
        try await seedCache([
            item("com.fav", title: "Fav", favorite: true),
            item("com.arch", title: "Arch", archived: true),
            item("com.manual", manual: true, favorite: true, archived: true)
        ])
        connection.fetchAppsHandler = {
            [playApp("com.fav", name: "Fav renamed"), playApp("com.arch", name: "Arch"), playApp("com.new", name: "New")]
        }
        let sut = makeSUT()

        await sut.load()

        let byPackage = Dictionary(uniqueKeysWithValues: sut.uiState.apps.map { ($0.packageName, $0) })
        XCTAssertEqual(byPackage["com.fav"]?.isFavorite, true)
        XCTAssertEqual(byPackage["com.fav"]?.title, "Fav renamed")
        XCTAssertEqual(byPackage["com.arch"]?.isArchived, true)
        XCTAssertEqual(byPackage["com.manual"]?.isFavorite, true)
        XCTAssertEqual(byPackage["com.manual"]?.isArchived, true)
        XCTAssertEqual(byPackage["com.new"]?.isFavorite, false)
        XCTAssertEqual(byPackage["com.new"]?.isArchived, false)
        let cached = try await cachedApps()
        XCTAssertEqual(cached?.first { $0.packageName == "com.arch" }?.isArchived, true, "Persisted after the sync")
    }

    func testMergeKeepsFlagsWhenAManualAppStartsComingFromTheAPI() {
        let merged = GooglePlayAppListSync.merge(
            remote: [playApp("com.listed", name: "Listed")],
            into: [item("com.listed", manual: true, favorite: true, archived: true)]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertFalse(merged[0].isManuallyAdded)
        XCTAssertTrue(merged[0].isFavorite)
        XCTAssertTrue(merged[0].isArchived)
    }

    func testArchivedAppsReleaseStatusIsNotRefreshed() async throws {
        try await seedCache([item("com.live", title: "Live"), item("com.arch", title: "Arch", archived: true)])
        connection.fetchAppsHandler = { [playApp("com.live", name: "Live"), playApp("com.arch", name: "Arch")] }
        let sut = makeSUT()

        await sut.refresh()

        XCTAssertFalse(connection.releaseSummaryRequests.contains { $0.packageName == "com.arch" })
        XCTAssertTrue(connection.releaseSummaryRequests.contains { $0.packageName == "com.live" })
    }

    // MARK: - Cached data from before the flags

    func testListCachedBeforeTheFlagsExistedDecodesUnflagged() throws {
        let json = #"[{"id":"com.a","packageName":"com.a","title":"A","isManuallyAdded":false,"iconUrl":"https://example.com/a.png"}]"#

        let items = try JSONDecoder().decode([GooglePlayAppItem].self, from: Data(json.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].isFavorite)
        XCTAssertFalse(items[0].isArchived)
        XCTAssertEqual(items[0].iconUrl, "https://example.com/a.png")
    }

    func testFlagsSurviveACacheRoundTrip() throws {
        let original = item("com.a", title: "A", favorite: true, archived: true)

        let decoded = try JSONDecoder().decode(GooglePlayAppItem.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Widgets

    func testDashboardSourcesSkipArchivedApps() async throws {
        try await seedCache([item("com.live", title: "Live"), item("com.arch", title: "Arch", archived: true)])

        let sources = await HomeWidgetDataLoader.loadGooglePlaySources(
            storage: storage,
            accounts: [account.id: account],
            requiring: .version,
            includesReleaseCaches: false,
            featureFlags: .googlePlayOn
        )

        XCTAssertEqual(sources.map(\.app.packageName), ["com.live"])
    }
}

// MARK: - Background sync

final class GooglePlayAccountSyncArchiveTests: XCTestCase {

    func testBackgroundSyncKeepsFlagsAndSkipsArchivedAppsReleaseStatusAndReviews() async throws {
        let storage = MockPersistentStorable()
        let connection = MockGooglePlayAccountConnection()
        let account = AccountModel(name: "Play Team", providerType: .googlePlay)
        let key = GooglePlayAppItem.cacheKey(accountId: account.id)
        try await storage.save([
            item("com.live", title: "Live", favorite: true),
            item("com.arch", title: "Arch", archived: true)
        ], id: key)
        connection.fetchAppsHandler = { [playApp("com.live", name: "Live"), playApp("com.arch", name: "Arch")] }

        _ = await GooglePlayAccountSync(account: account, connection: connection, storage: storage, mode: .full).run()

        let list = try await storage.fetch([GooglePlayAppItem].self, id: key)
        XCTAssertEqual(list?.first { $0.packageName == "com.live" }?.isFavorite, true)
        XCTAssertEqual(list?.first { $0.packageName == "com.arch" }?.isArchived, true)
        XCTAssertFalse(connection.releaseSummaryRequests.contains { $0.packageName == "com.arch" })
        XCTAssertFalse(connection.reviewsPageRequests.contains { $0.packageName == "com.arch" })
        XCTAssertTrue(connection.reviewsPageRequests.contains { $0.packageName == "com.live" })
    }
}

// MARK: - Fixtures

private func playApp(_ packageName: String, name: String) -> StackProtocols.AppInfo {
    StackProtocols.AppInfo(id: packageName, name: name, bundleId: packageName, platform: "ANDROID")
}

private func item(
    _ packageName: String,
    title: String? = nil,
    manual: Bool = false,
    favorite: Bool = false,
    archived: Bool = false
) -> GooglePlayAppItem {
    GooglePlayAppItem(
        id: packageName,
        packageName: packageName,
        title: title,
        isManuallyAdded: manual,
        isFavorite: favorite,
        isArchived: archived
    )
}
