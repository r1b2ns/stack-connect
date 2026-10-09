import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

@MainActor
final class GooglePlayAppListViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayAccountConnection!
    private var accessChecker: MockGooglePlayAppAccessChecker!

    private let account = AccountModel(name: "Play Team", providerType: .googlePlay)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayAccountConnection()
        accessChecker = MockGooglePlayAppAccessChecker()
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        accessChecker = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// - Parameters:
    ///   - account: defaults to the created, unrestricted `account`. Any other
    ///     account gets the same stored credentials.
    ///   - online: what the injected connectivity probe answers.
    private func makeSUT(account: AccountModel? = nil, online: Bool = true) -> GooglePlayAppListViewModel {
        let checker = accessChecker!
        let account = account ?? self.account
        if account.id != self.account.id {
            keychain.setObject(
                GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
                forKey: "credentials.\(account.id)"
            )
        }
        return GooglePlayAppListViewModel(
            account: account,
            keychain: keychain,
            storage: storage,
            connectionFactory: connection.appListFactory,
            accessCheckerFactory: { _ in checker },
            connectivity: MockConnectivityProviding(online: online)
        )
    }

    /// An imported account with the given `apps` permissions and per-app scope.
    private func importedAccount(
        apps: [AccountPermission] = AccountPermission.allCases,
        appsBundles: [String]? = nil
    ) -> AccountModel {
        AccountModel(
            name: "Imported Play",
            providerType: .googlePlay,
            rules: AccountRules(apps: apps),
            origin: .imported,
            appsBundles: appsBundles
        )
    }

    private var cacheKey: String {
        GooglePlayAppItem.cacheKey(accountId: account.id)
    }

    private func seedCache(_ apps: [GooglePlayAppItem], accountId: String? = nil) async throws {
        try await storage.save(apps, id: GooglePlayAppItem.cacheKey(accountId: accountId ?? account.id))
    }

    private func cachedApps(accountId: String? = nil) async throws -> [GooglePlayAppItem]? {
        try await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: accountId ?? account.id))
    }

    /// How many times the Play app list was written to storage so far.
    private func listSaveCount() async -> Int {
        await storage.saveCallCount[String(describing: [GooglePlayAppItem].self)] ?? 0
    }

    // MARK: - Offline-first load

    func testLoadShowsTheCacheBeforeSyncingFromTheAPI() async throws {
        try await seedCache([playItem("com.cached.app", title: "Cached", manual: false)])
        let sut = makeSUT()
        connection.fetchAppsHandler = {
            // While the API call is in flight, the cached list is already shown
            // with the sync toast.
            let (visible, toast, loading) = await MainActor.run {
                (sut.uiState.apps.map(\.packageName), sut.uiState.showSyncToast, sut.uiState.isLoading)
            }
            XCTAssertEqual(visible, ["com.cached.app"])
            XCTAssertTrue(toast)
            XCTAssertFalse(loading, "Cached data must not be hidden behind a spinner")
            return [playApp("com.fresh.app", name: "Fresh")]
        }

        await sut.load()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.fresh.app"])
        XCTAssertNil(sut.uiState.error)
        XCTAssertFalse(sut.uiState.isSyncing)
        XCTAssertEqual(connection.fetchAppsCallCount, 1)
        let cached = try await cachedApps()
        XCTAssertEqual(cached?.map(\.packageName), ["com.fresh.app"], "The synced list is persisted")
    }

    func testLoadWithoutCacheSyncsAndPersistsTheList() async throws {
        connection.fetchAppsHandler = {
            [playApp("com.b.app", name: "Bravo"), playApp("com.a.app", name: "alpha")]
        }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.apps.map(\.displayName), ["alpha", "Bravo"], "Sorted case-insensitively")
        XCTAssertFalse(sut.uiState.showSyncToast, "No toast when there was nothing cached")
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertTrue(sut.uiState.apps.allSatisfy { !$0.isManuallyAdded })
        let cached = try await cachedApps()
        XCTAssertEqual(cached?.count, 2)
    }

    func testLoadMergesManualAppsAndDedupesByPackageName() async throws {
        try await seedCache([
            playItem("com.manual.only", manual: true),
            playItem("com.manual.now.listed", manual: true),
            playItem("com.stale.api.app", title: "Gone", manual: false)
        ])
        connection.fetchAppsHandler = {
            [
                playApp("com.api.app", name: "Api App"),
                playApp("com.manual.now.listed", name: "Now Listed")
            ]
        }
        let sut = makeSUT()

        await sut.load()

        let byPackage = Dictionary(uniqueKeysWithValues: sut.uiState.apps.map { ($0.packageName, $0) })
        XCTAssertEqual(Set(byPackage.keys), ["com.api.app", "com.manual.now.listed", "com.manual.only"])
        XCTAssertEqual(sut.uiState.apps.count, 3, "No duplicate package names")
        XCTAssertEqual(byPackage["com.manual.now.listed"]?.isManuallyAdded, false, "The API entry wins")
        XCTAssertEqual(byPackage["com.manual.now.listed"]?.displayName, "Now Listed")
        XCTAssertEqual(byPackage["com.manual.only"]?.isManuallyAdded, true, "Manual apps the API omits are kept")
        XCTAssertNil(byPackage["com.stale.api.app"], "API apps no longer returned are dropped")
    }

    func testMergeDedupesRepeatedRemoteEntries() {
        let merged = GooglePlayAppListViewModel.merge(
            remote: [playApp("com.dup", name: "First"), playApp("com.dup", name: "Second")],
            into: []
        )

        XCTAssertEqual(merged.map(\.packageName), ["com.dup"])
        XCTAssertEqual(merged.first?.displayName, "First")
    }

    // MARK: - Failures

    func testSyncFailureKeepsTheCacheAndSurfacesTheError() async throws {
        let cachedList = [playItem("com.cached.app", title: "Cached", manual: false)]
        try await seedCache(cachedList)
        connection.fetchAppsHandler = { throw StackError.Http(status: 503, message: "backend error") }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.apps, cachedList)
        XCTAssertEqual(
            sut.uiState.error,
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 503, message: ""))
        )
        XCTAssertFalse(sut.uiState.isSyncing)
        let cached = try await cachedApps()
        XCTAssertEqual(cached, cachedList, "A failed sync must not touch the cache")
    }

    func testSyncFailureWithoutCacheShowsTheTranslatedAuthError() async {
        let detail = "Enable the Google Play Developer Reporting API: https://console.developers.google.com/apis/api/playdeveloperreporting.googleapis.com"
        connection.fetchAppsHandler = { throw StackError.Auth(message: detail) }
        let sut = makeSUT()

        await sut.load()

        XCTAssertTrue(sut.uiState.apps.isEmpty)
        XCTAssertEqual(sut.uiState.error, GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: detail)))
        XCTAssertTrue(sut.uiState.error?.contains(detail) == true)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    func testOfflineWithCacheKeepsTheListWithoutASecondWarning() async throws {
        let cachedList = [playItem("com.cached.app", manual: true)]
        try await seedCache(cachedList)
        connection.fetchAppsHandler = { throw OfflineError.noConnection }
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.apps, cachedList)
        XCTAssertNil(sut.uiState.error, "The global offline banner already covers this")
        XCTAssertFalse(sut.uiState.isSyncing)
    }

    func testOfflineWithoutCacheExplainsWhyTheListIsEmpty() async {
        connection.fetchAppsHandler = { throw OfflineError.noConnection }
        let sut = makeSUT()

        await sut.load()

        XCTAssertTrue(sut.uiState.apps.isEmpty)
        XCTAssertEqual(sut.uiState.error, OfflineError.noConnection.localizedDescription)
    }

    func testMissingCredentialsShowsTheCacheAndSkipsTheSync() async throws {
        keychain.removeObject(forKey: "credentials.\(account.id)")
        try await seedCache([playItem("com.cached.app", manual: false)])
        let sut = makeSUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.cached.app"])
        XCTAssertEqual(sut.uiState.error, String(localized: "No credentials found for this account."))
        XCTAssertEqual(connection.fetchAppsCallCount, 0)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - Manual add / remove

    func testAddAppChecksAccessAndPersistsItAsManual() async throws {
        let sut = makeSUT()
        sut.uiState.showAddApp = true

        await sut.addApp(packageName: "  com.example.new ")

        XCTAssertEqual(accessChecker.checkedPackageNames, ["com.example.new"])
        XCTAssertEqual(sut.uiState.apps, [playItem("com.example.new", manual: true)], "No public icon: placeholder")
        XCTAssertEqual(connection.iconRequests, ["com.example.new"])
        XCTAssertFalse(sut.uiState.showAddApp)
        XCTAssertNil(sut.uiState.addError)
        XCTAssertNotNil(sut.uiState.toastMessage)
        let cached = try await cachedApps()
        XCTAssertEqual(cached, [playItem("com.example.new", manual: true)])
    }

    func testAddAppAccessFailureShowsTheErrorAndAddsNothing() async throws {
        accessChecker.error = NSError(domain: "play", code: 403, userInfo: [NSLocalizedDescriptionKey: "No access"])
        let sut = makeSUT()

        await sut.addApp(packageName: "com.example.denied")

        XCTAssertEqual(sut.uiState.addError, "No access")
        XCTAssertTrue(sut.uiState.apps.isEmpty)
        XCTAssertFalse(sut.uiState.isAdding)
        XCTAssertTrue(connection.iconRequests.isEmpty)
        let cached = try await cachedApps()
        XCTAssertNil(cached)
    }

    func testAddAppAlreadyListedIsRejectedWithoutACheck() async {
        let sut = makeSUT()
        sut.uiState.apps = [playItem("com.example.app", manual: false)]

        await sut.addApp(packageName: "com.example.app")

        XCTAssertEqual(sut.uiState.addError, String(localized: "This app is already in the list."))
        XCTAssertTrue(accessChecker.checkedPackageNames.isEmpty)
    }

    func testRemoveAppPersistsTheRemainingList() async throws {
        let keep = playItem("com.keep", manual: false)
        let drop = playItem("com.drop", manual: true)
        try await seedCache([keep, drop])
        let sut = makeSUT()
        sut.uiState.apps = [keep, drop]

        await sut.removeApp(drop)

        XCTAssertEqual(sut.uiState.apps, [keep])
        let cached = try await cachedApps()
        XCTAssertEqual(cached, [keep])
    }
}

// MARK: - Per-app scope & rules (imported accounts)

extension GooglePlayAppListViewModelTests {

    func testNilScopeShowsEveryApp() async {
        connection.fetchAppsHandler = { [playApp("com.a", name: "A"), playApp("com.b", name: "B")] }
        let sut = makeSUT(account: importedAccount(appsBundles: nil))

        await sut.load()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.a", "com.b"])
    }

    func testEmptyScopeShowsEveryApp() async {
        connection.fetchAppsHandler = { [playApp("com.a", name: "A"), playApp("com.b", name: "B")] }
        let sut = makeSUT(account: importedAccount(appsBundles: []))

        await sut.load()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.a", "com.b"])
    }

    func testNonEmptyScopeShowsAndPersistsOnlyTheSharedApps() async throws {
        let scoped = importedAccount(appsBundles: ["com.b"])
        connection.fetchAppsHandler = { [playApp("com.a", name: "A"), playApp("com.b", name: "B")] }
        let sut = makeSUT(account: scoped)

        await sut.load()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.b"])
        let cached = try await cachedApps(accountId: scoped.id)
        XCTAssertEqual(cached?.map(\.packageName), ["com.b"], "Apps outside the scope are never persisted")
    }

    func testNonEmptyScopeHidesCachedAppsOutsideItOffline() async throws {
        let scoped = importedAccount(appsBundles: ["com.b"])
        try await seedCache(
            [playItem("com.a", manual: true), playItem("com.b", manual: false)],
            accountId: scoped.id
        )
        connection.fetchAppsHandler = { throw OfflineError.noConnection }
        let sut = makeSUT(account: scoped)

        await sut.load()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.b"])
    }

    func testRulesDriveTheAddAndDeleteCapabilities() {
        XCTAssertTrue(makeSUT().uiState.canAddApps, "Created accounts have every permission")
        XCTAssertTrue(makeSUT().uiState.canDeleteApps)

        let viewOnly = makeSUT(account: importedAccount(apps: [.view]))
        XCTAssertFalse(viewOnly.uiState.canAddApps)
        XCTAssertFalse(viewOnly.uiState.canDeleteApps)

        let addOnly = makeSUT(account: importedAccount(apps: [.add]))
        XCTAssertTrue(addOnly.uiState.canAddApps)
        XCTAssertFalse(addOnly.uiState.canDeleteApps)
    }

    func testAddAppWithoutAddPermissionIsRejectedWithoutACheck() async throws {
        let account = importedAccount(apps: [.view, .delete])
        let sut = makeSUT(account: account)

        await sut.addApp(packageName: "com.example.new")

        XCTAssertEqual(sut.uiState.addError, String(localized: "This account doesn't have permission to add apps."))
        XCTAssertTrue(accessChecker.checkedPackageNames.isEmpty)
        XCTAssertTrue(sut.uiState.apps.isEmpty)
        let cached = try await cachedApps(accountId: account.id)
        XCTAssertNil(cached)
    }

    func testAddAppOutsideTheScopeIsRejectedWithoutACheck() async {
        let sut = makeSUT(account: importedAccount(apps: [.add], appsBundles: ["com.shared"]))

        await sut.addApp(packageName: "com.not.shared")

        XCTAssertEqual(
            sut.uiState.addError,
            String(localized: "This app isn't included in the apps shared with this account.")
        )
        XCTAssertTrue(accessChecker.checkedPackageNames.isEmpty)
        XCTAssertTrue(sut.uiState.apps.isEmpty)
    }

    func testAddAppInsideTheScopeWithAddPermissionIsAdded() async {
        let sut = makeSUT(account: importedAccount(apps: [.add], appsBundles: ["com.shared"]))

        await sut.addApp(packageName: "com.shared")

        XCTAssertNil(sut.uiState.addError)
        XCTAssertEqual(accessChecker.checkedPackageNames, ["com.shared"])
        XCTAssertEqual(sut.uiState.apps, [playItem("com.shared", manual: true)])
    }

    func testRemoveAppWithoutDeletePermissionKeepsTheApp() async throws {
        let account = importedAccount(apps: [.view, .add])
        let manual = playItem("com.manual", manual: true)
        try await seedCache([manual], accountId: account.id)
        let sut = makeSUT(account: account)
        sut.uiState.apps = [manual]

        await sut.removeApp(manual)

        XCTAssertEqual(sut.uiState.apps, [manual])
        XCTAssertNotNil(sut.uiState.toastMessage)
        let cached = try await cachedApps(accountId: account.id)
        XCTAssertEqual(cached, [manual], "Nothing persisted")
    }

    func testRemoveAppWithDeletePermissionRemovesIt() async throws {
        let account = importedAccount(apps: [.delete])
        let manual = playItem("com.manual", manual: true)
        try await seedCache([manual], accountId: account.id)
        let sut = makeSUT(account: account)
        sut.uiState.apps = [manual]

        await sut.removeApp(manual)

        XCTAssertTrue(sut.uiState.apps.isEmpty)
        let cached = try await cachedApps(accountId: account.id)
        XCTAssertEqual(cached, [])
    }
}

// MARK: - App icons (public store page, plan D18)

extension GooglePlayAppListViewModelTests {

    func testMergeCarriesCachedIconsOverByPackageName() {
        let current = [
            playItem("com.api", title: "Api", manual: false, icon: iconURL("com.api")),
            playItem("com.manual.listed", manual: true, icon: iconURL("com.manual.listed")),
            playItem("com.manual.only", manual: true, icon: iconURL("com.manual.only")),
            playItem("com.no.icon", manual: false)
        ]

        let merged = GooglePlayAppListViewModel.merge(
            remote: [
                playApp("com.api", name: "Api"),
                playApp("com.manual.listed", name: "Listed"),
                playApp("com.no.icon", name: "No Icon"),
                playApp("com.new", name: "New")
            ],
            into: current
        )

        let byPackage = Dictionary(uniqueKeysWithValues: merged.map { ($0.packageName, $0) })
        XCTAssertEqual(Set(byPackage.keys), ["com.api", "com.manual.listed", "com.manual.only", "com.no.icon", "com.new"])
        XCTAssertEqual(byPackage["com.api"]?.iconUrl, iconURL("com.api"))
        XCTAssertEqual(byPackage["com.manual.listed"]?.iconUrl, iconURL("com.manual.listed"), "The API entry wins but keeps the icon")
        XCTAssertEqual(byPackage["com.manual.listed"]?.isManuallyAdded, false)
        XCTAssertEqual(byPackage["com.manual.only"]?.iconUrl, iconURL("com.manual.only"))
        XCTAssertNil(byPackage["com.no.icon"]?.iconUrl)
        XCTAssertNil(byPackage["com.new"]?.iconUrl)
    }

    func testLoadFetchesOnlyMissingIconsAndPersistsThemOnce() async throws {
        try await seedCache([
            playItem("com.has.icon", title: "Has", manual: false, icon: "https://example.com/cached.png"),
            playItem("com.missing", title: "Missing", manual: false)
        ])
        connection.fetchAppsHandler = {
            [playApp("com.has.icon", name: "Has"), playApp("com.missing", name: "Missing"), playApp("com.new", name: "New")]
        }
        connection.fetchIconUrlHandler = { iconURL($0) }
        let sut = makeSUT()
        let savesBefore = await listSaveCount()

        await sut.load()

        XCTAssertEqual(connection.iconRequests.sorted(), ["com.missing", "com.new"], "Apps with an icon are never asked again")
        let byPackage = Dictionary(uniqueKeysWithValues: sut.uiState.apps.map { ($0.packageName, $0) })
        XCTAssertEqual(byPackage["com.has.icon"]?.iconUrl, "https://example.com/cached.png")
        XCTAssertEqual(byPackage["com.missing"]?.iconUrl, iconURL("com.missing"))
        XCTAssertEqual(byPackage["com.new"]?.iconUrl, iconURL("com.new"))
        XCTAssertFalse(sut.uiState.isSyncing)
        XCTAssertFalse(sut.uiState.isLoading)

        let cached = try await cachedApps()
        XCTAssertEqual(cached, sut.uiState.apps, "The icons are persisted with the list")
        let saves = await listSaveCount()
        XCTAssertEqual(saves - savesBefore, 2, "One save for the sync, one for all the icons")

        // Cached icons are reused on the next load: nothing is fetched again.
        await sut.load()
        XCTAssertEqual(connection.iconRequests.count, 2)
    }

    func testIconsArriveAfterTheListIsShown() async {
        let iconRequestSawTheList = LockedFlag()
        connection.fetchAppsHandler = { [playApp("com.a", name: "A")] }
        let sut = makeSUT()
        connection.fetchIconUrlHandler = { _ in
            let (visible, loading) = await MainActor.run { (sut.uiState.apps.map(\.packageName), sut.uiState.isLoading) }
            iconRequestSawTheList.set(visible == ["com.a"] && !loading)
            return nil
        }

        await sut.load()

        XCTAssertTrue(iconRequestSawTheList.value, "Icons must never hold the list back")
    }

    func testMissingPublicIconKeepsThePlaceholderAndIsAskedAgainNextLoad() async throws {
        connection.fetchAppsHandler = { [playApp("com.unpublished", name: "Draft")] }
        let sut = makeSUT()   // default icon handler: no public icon

        await sut.load()

        XCTAssertEqual(connection.iconRequests, ["com.unpublished"])
        XCTAssertNil(sut.uiState.apps.first?.iconUrl)
        let savesAfterFirstLoad = await listSaveCount()
        XCTAssertEqual(savesAfterFirstLoad, 1, "Nothing to persist when no icon was found")

        await sut.load()

        XCTAssertEqual(connection.iconRequests, ["com.unpublished", "com.unpublished"])
    }

    func testIconsAreFetchedForTheCachedListWhenTheSyncFails() async throws {
        try await seedCache([playItem("com.cached", title: "Cached", manual: false)])
        connection.fetchAppsHandler = { throw StackError.Http(status: 503, message: "backend error") }
        connection.fetchIconUrlHandler = { iconURL($0) }
        let sut = makeSUT()

        await sut.load()

        XCTAssertNotNil(sut.uiState.error, "The sync failure is still reported")
        XCTAssertEqual(connection.iconRequests, ["com.cached"])
        XCTAssertEqual(sut.uiState.apps.first?.iconUrl, iconURL("com.cached"))
        let cached = try await cachedApps()
        XCTAssertEqual(cached?.first?.iconUrl, iconURL("com.cached"))
    }

    func testNoIconsAreFetchedWhenTheSyncFailsOffline() async throws {
        try await seedCache([playItem("com.cached", manual: false)])
        connection.fetchAppsHandler = { throw OfflineError.noConnection }
        let sut = makeSUT()

        await sut.load()

        XCTAssertTrue(connection.iconRequests.isEmpty)
        XCTAssertFalse(sut.uiState.isSyncing)
    }

    func testNoIconsAreFetchedWhileTheDeviceIsOffline() async {
        connection.fetchAppsHandler = { [playApp("com.a", name: "A")] }
        connection.fetchIconUrlHandler = { iconURL($0) }
        let sut = makeSUT(online: false)

        await sut.load()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.a"])
        XCTAssertTrue(connection.iconRequests.isEmpty)
        XCTAssertNil(sut.uiState.apps.first?.iconUrl)
    }

    func testIconsAreNeverFetchedForAppsOutsideTheScope() async throws {
        let scoped = importedAccount(appsBundles: ["com.a", "com.b"])
        try await seedCache(
            [playItem("com.a", manual: false), playItem("com.out", manual: true)],
            accountId: scoped.id
        )
        connection.fetchAppsHandler = {
            [playApp("com.a", name: "A"), playApp("com.b", name: "B"), playApp("com.out", name: "Out")]
        }
        connection.fetchIconUrlHandler = { iconURL($0) }
        let sut = makeSUT(account: scoped)

        await sut.load()

        XCTAssertEqual(connection.iconRequests.sorted(), ["com.a", "com.b"])
        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.a", "com.b"])
    }

    func testIconFetchesAreBoundedInFlight() async {
        let packages = (0..<10).map { "com.app\($0)" }
        connection.fetchAppsHandler = { packages.map { playApp($0, name: $0) } }
        let gate = AsyncGate()
        connection.fetchIconUrlHandler = { packageName in
            await gate.wait()
            return iconURL(packageName)
        }
        let sut = makeSUT()
        let limit = GooglePlayAppListViewModel.maxConcurrentIconFetches

        let loading = Task { await sut.load() }
        await gate.waitForArrivals(limit + 1)   // bounded: returns once nothing else can arrive
        let startedWhileBlocked = await gate.arrivals
        await gate.open()
        await loading.value

        XCTAssertEqual(startedWhileBlocked, limit, "No more than \(limit) lookups at once")
        XCTAssertLessThanOrEqual(connection.maxIconFetchesInFlight, limit)
        XCTAssertEqual(connection.iconRequests.sorted(), packages.sorted(), "Every app is still asked once")
        XCTAssertTrue(sut.uiState.apps.allSatisfy { $0.iconUrl == iconURL($0.packageName) })
    }

    func testIconsAreAppliedOntoTheCurrentListWithoutClobberingAConcurrentAddOrRemoval() async throws {
        connection.fetchAppsHandler = { [playApp("com.keep", name: "Keep"), playApp("com.drop", name: "Drop")] }
        let gate = AsyncGate()
        connection.fetchIconUrlHandler = { packageName in
            await gate.wait()
            return iconURL(packageName)
        }
        let sut = makeSUT()

        // The load's icon pass is in flight for both apps…
        let loading = Task { await sut.load() }
        await gate.waitForArrivals(2)
        // …while the user adds an app (its own icon lookup joins in) and removes another.
        let adding = Task { await sut.addApp(packageName: "com.added") }
        await gate.waitForArrivals(3)
        let drop = try XCTUnwrap(sut.uiState.apps.first { $0.packageName == "com.drop" })
        await sut.removeApp(drop)

        await gate.open()
        await loading.value
        await adding.value

        XCTAssertEqual(connection.iconRequests.sorted(), ["com.added", "com.drop", "com.keep"], "Each app asked once")
        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.added", "com.keep"], "The removal and the addition both survive")
        XCTAssertTrue(sut.uiState.apps.allSatisfy { $0.iconUrl == iconURL($0.packageName) })
        let cached = try await cachedApps()
        XCTAssertEqual(cached, sut.uiState.apps)
    }

    func testAddAppFetchesOnlyTheNewAppsIconAndPersistsIt() async throws {
        connection.fetchIconUrlHandler = { iconURL($0) }
        let sut = makeSUT()
        sut.uiState.apps = [playItem("com.other", manual: false)]

        await sut.addApp(packageName: "com.example.new")

        XCTAssertEqual(connection.iconRequests, ["com.example.new"])
        let added = sut.uiState.apps.first { $0.packageName == "com.example.new" }
        XCTAssertEqual(added?.iconUrl, iconURL("com.example.new"))
        XCTAssertNil(sut.uiState.apps.first { $0.packageName == "com.other" }?.iconUrl)
        XCTAssertFalse(sut.uiState.isAdding)
        let cached = try await cachedApps()
        XCTAssertEqual(cached?.first { $0.packageName == "com.example.new" }?.iconUrl, iconURL("com.example.new"))
    }

    func testAddAppWhileOfflineSkipsTheIconLookup() async {
        connection.fetchIconUrlHandler = { iconURL($0) }
        let sut = makeSUT(online: false)

        await sut.addApp(packageName: "com.example.new")

        XCTAssertEqual(sut.uiState.apps, [playItem("com.example.new", manual: true)])
        XCTAssertTrue(connection.iconRequests.isEmpty)
    }
}

// MARK: - Fixtures

/// File-scope (nonisolated) so the `@Sendable` mock handlers can build them too.
private func playApp(_ packageName: String, name: String) -> StackProtocols.AppInfo {
    StackProtocols.AppInfo(id: packageName, name: name, bundleId: packageName, platform: "ANDROID")
}

private func playItem(_ packageName: String, title: String? = nil, manual: Bool, icon: String? = nil) -> GooglePlayAppItem {
    GooglePlayAppItem(id: packageName, packageName: packageName, title: title, isManuallyAdded: manual, iconUrl: icon)
}

/// The icon URL the mock "store page" hands out for `packageName`.
private func iconURL(_ packageName: String) -> String {
    "https://play-lh.googleusercontent.com/\(packageName)=s512"
}
