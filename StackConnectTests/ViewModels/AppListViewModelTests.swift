import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AppListViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        try await super.tearDown()
    }

    private func seedApp(_ id: String, bundleId: String, accountId: String) async throws {
        let app = AppModel(id: id, name: id.uppercased(), bundleId: bundleId, accountId: accountId)
        try await storage.save(app, id: "\(accountId).\(id)")
    }

    /// Read-side defense-in-depth: cached apps outside the per-app scope must be
    /// filtered out of the visible list. No credentials are set, so `loadApps`
    /// returns right after the offline-first cache read.
    func testLoadAppsFiltersCachedAppsByScope() async throws {
        let account = AccountModel(
            name: "Scoped",
            providerType: .apple,
            origin: .imported,
            appsBundles: ["com.a", "com.c"]
        )
        try await seedApp("a", bundleId: "com.a", accountId: account.id)
        try await seedApp("b", bundleId: "com.b", accountId: account.id)
        try await seedApp("c", bundleId: "com.c", accountId: account.id)

        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain)
        await sut.loadApps()

        let bundles = Set(sut.uiState.apps.map(\.bundleId))
        XCTAssertEqual(bundles, ["com.a", "com.c"])
        XCTAssertFalse(bundles.contains("com.b"))
    }

    /// nil scope ⇒ all cached apps remain visible.
    func testLoadAppsWithUnrestrictedScopeKeepsAllCachedApps() async throws {
        let account = AccountModel(name: "Free", providerType: .apple, appsBundles: nil)
        try await seedApp("a", bundleId: "com.a", accountId: account.id)
        try await seedApp("b", bundleId: "com.b", accountId: account.id)

        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain)
        await sut.loadApps()

        XCTAssertEqual(Set(sut.uiState.apps.map(\.bundleId)), ["com.a", "com.b"])
    }

    // MARK: - Cached phased releases

    /// Seeds a cached app carrying a per-platform version id, then its cached
    /// phased release under the production `"phased.{versionId}"` key.
    private func seedAppWithVersion(
        _ id: String,
        bundleId: String,
        accountId: String,
        versionId: String
    ) async throws {
        let app = AppModel(
            id: id,
            name: id.uppercased(),
            bundleId: bundleId,
            accountId: accountId,
            platformVersions: [
                AppPlatformVersion(
                    platform: "IOS",
                    appStoreState: .readyForSale,
                    versionString: "1.0.0",
                    id: versionId
                )
            ]
        )
        try await storage.save(app, id: "\(accountId).\(id)")
    }

    /// Offline-first: with no credentials the network path returns early, yet
    /// `loadApps` must still hydrate `phasedByVersionId` from the cached
    /// `"phased.{versionId}"` entry for the app's per-platform version id.
    func testLoadAppsPopulatesPhasedFromCachedVersionId() async throws {
        let account = AccountModel(name: "Phased", providerType: .apple)
        try await seedAppWithVersion("a", bundleId: "com.a", accountId: account.id, versionId: "v1")
        try await storage.save(
            PhasedReleaseModel(id: "phased.v1", state: .active, currentDayNumber: 1),
            id: "phased.v1"
        )

        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain)
        await sut.loadApps()

        XCTAssertEqual(sut.uiState.apps.count, 1)
        XCTAssertEqual(sut.uiState.phasedByVersionId["v1"]?.currentDayNumber, 1)
        XCTAssertEqual(sut.uiState.phasedByVersionId["v1"]?.state, .active)
    }

    /// No cached phased entry ⇒ the map stays empty (caller shows the plain badge).
    func testLoadAppsLeavesPhasedEmptyWhenNoneCached() async throws {
        let account = AccountModel(name: "NoPhased", providerType: .apple)
        try await seedAppWithVersion("a", bundleId: "com.a", accountId: account.id, versionId: "v1")

        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain)
        await sut.loadApps()

        XCTAssertNil(sut.uiState.phasedByVersionId["v1"])
        XCTAssertTrue(sut.uiState.phasedByVersionId.isEmpty)
    }

    // MARK: - Analytics events

    private func makeSUTWithCachedApp(analytics: MockAnalyticsTracker) async throws -> (AppListViewModel, AppModel) {
        let account = AccountModel(name: "Team", providerType: .apple)
        try await seedApp("a", bundleId: "com.a", accountId: account.id)
        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain, analytics: analytics)
        await sut.loadApps()
        let app = try XCTUnwrap(sut.uiState.apps.first)
        return (sut, app)
    }

    func testLoadAppsTracksNothing() async throws {
        let analytics = MockAnalyticsTracker()
        _ = try await makeSUTWithCachedApp(analytics: analytics)

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testRefreshWithoutCredentialsTracksFailure() async throws {
        let analytics = MockAnalyticsTracker()
        let (sut, _) = try await makeSUTWithCachedApp(analytics: analytics)

        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .appList, result: .failure)])
    }

    func testToggleFavoriteTracksTapAndSuccess() async throws {
        let analytics = MockAnalyticsTracker()
        let (sut, app) = try await makeSUTWithCachedApp(analytics: analytics)

        await sut.toggleFavorite(app: app)

        XCTAssertEqual(analytics.taps(of: .favorite), [.buttonTap(.favorite, on: .appList)])
        XCTAssertEqual(analytics.actions(of: .toggleFavorite), [
            .action(.toggleFavorite, on: .appList, result: .success, parameters: [AnalyticsParameterKey.enabled: .bool(true)])
        ])
    }

    func testToggleArchiveTracksFailureWhenSaveFails() async throws {
        let analytics = MockAnalyticsTracker()
        let (sut, app) = try await makeSUTWithCachedApp(analytics: analytics)
        await storage.failSave(AppModel.self)

        await sut.toggleArchive(app: app)

        XCTAssertEqual(analytics.taps(of: .archive).count, 1)
        XCTAssertEqual(analytics.results(of: .toggleArchive), [.failure])
    }
}
