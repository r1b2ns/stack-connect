import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class GooglePlayArchivedAppsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var analytics: MockAnalyticsTracker!
    private var dashboardRefreshes = 0
    private let account = AccountModel(name: "Play Team", providerType: .googlePlay)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        analytics = MockAnalyticsTracker()
        dashboardRefreshes = 0
    }

    override func tearDown() async throws {
        storage = nil
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var cacheKey: String {
        GooglePlayAppItem.cacheKey(accountId: account.id)
    }

    private func makeSUT(account: AccountModel? = nil) -> GooglePlayArchivedAppsViewModel {
        GooglePlayArchivedAppsViewModel(
            account: account ?? self.account,
            storage: storage,
            analytics: analytics,
            dashboardDidChange: { [weak self] _ in self?.dashboardRefreshes += 1 }
        )
    }

    private func seed(_ apps: [GooglePlayAppItem], accountId: String? = nil) async throws {
        try await storage.save(apps, id: GooglePlayAppItem.cacheKey(accountId: accountId ?? account.id))
    }

    // MARK: - Load

    func testLoadShowsOnlyArchivedAppsSortedByNameWithoutTracking() async throws {
        try await seed([
            item("com.live", title: "Live"),
            item("com.z", title: "zulu", archived: true),
            item("com.a", title: "Alpha", archived: true)
        ])
        let sut = makeSUT()

        await sut.loadApps()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.a", "com.z"])
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testLoadIgnoresOtherAccountsAndAppsOutsideTheScope() async throws {
        let scoped = AccountModel(name: "Imported", providerType: .googlePlay, rules: .allPermissions,
                                  origin: .imported, appsBundles: ["com.shared"])
        try await seed([item("com.shared", archived: true), item("com.private", archived: true)], accountId: scoped.id)
        try await seed([item("com.other.account", archived: true)])
        let sut = makeSUT(account: scoped)

        await sut.loadApps()

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.shared"])
    }

    func testLoadWithNothingCachedShowsNoApps() async {
        let sut = makeSUT()

        await sut.loadApps()

        XCTAssertTrue(sut.uiState.apps.isEmpty)
        XCTAssertTrue(sut.uiState.filteredApps.isEmpty)
    }

    func testSearchMatchesNameOrPackage() async throws {
        try await seed([item("com.alpha", title: "Alpha", archived: true), item("com.bravo", title: "Bravo", archived: true)])
        let sut = makeSUT()
        await sut.loadApps()

        sut.uiState.searchQuery = "BRAV"
        XCTAssertEqual(sut.uiState.filteredApps.map(\.packageName), ["com.bravo"])

        sut.uiState.searchQuery = "com.alpha"
        XCTAssertEqual(sut.uiState.filteredApps.map(\.packageName), ["com.alpha"])
    }

    func testRefreshTracksSuccess() async {
        let sut = makeSUT()

        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .googlePlayArchivedApps, result: .success)])
    }

    // MARK: - Unarchive

    func testUnarchiveClearsTheFlagKeepsTheRestAndRefreshesTheWidgets() async throws {
        try await seed([
            item("com.live", title: "Live", favorite: true),
            item("com.arch", title: "Arch", archived: true)
        ])
        let sut = makeSUT()
        await sut.loadApps()
        let app = try XCTUnwrap(sut.uiState.apps.first)

        await sut.unarchive(app: app)

        XCTAssertTrue(sut.uiState.apps.isEmpty)
        let stored = try await storage.fetch([GooglePlayAppItem].self, id: cacheKey)
        XCTAssertEqual(stored?.map(\.packageName), ["com.live", "com.arch"], "The rest of the list is untouched")
        XCTAssertEqual(stored?.first { $0.packageName == "com.arch" }?.isArchived, false)
        XCTAssertEqual(stored?.first { $0.packageName == "com.live" }?.isFavorite, true)
        XCTAssertEqual(dashboardRefreshes, 1)
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "App unarchived"))
        XCTAssertEqual(analytics.taps(of: .unarchive), [.buttonTap(.unarchive, on: .googlePlayArchivedApps)])
        XCTAssertEqual(analytics.actions(of: .toggleArchive), [
            .action(.toggleArchive, on: .googlePlayArchivedApps, result: .success, parameters: [AnalyticsParameterKey.enabled: .bool(false)])
        ])
    }

    func testUnarchiveKeepsTheAppWhenTheSaveFails() async throws {
        try await seed([item("com.arch", title: "Arch", archived: true)])
        let sut = makeSUT()
        await sut.loadApps()
        let app = try XCTUnwrap(sut.uiState.apps.first)
        await storage.failSave([GooglePlayAppItem].self)

        await sut.unarchive(app: app)

        XCTAssertEqual(sut.uiState.apps.map(\.packageName), ["com.arch"])
        XCTAssertEqual(dashboardRefreshes, 0)
        XCTAssertNil(sut.uiState.toastMessage)
        XCTAssertEqual(analytics.results(of: .toggleArchive), [.failure])
    }

    func testUnarchiveOfAnAppNoLongerStoredJustDropsIt() async throws {
        try await seed([item("com.arch", title: "Arch", archived: true)])
        let sut = makeSUT()
        await sut.loadApps()
        let app = try XCTUnwrap(sut.uiState.apps.first)
        try await seed([])

        await sut.unarchive(app: app)

        XCTAssertTrue(sut.uiState.apps.isEmpty)
        XCTAssertEqual(dashboardRefreshes, 0)
        XCTAssertTrue(analytics.actions(of: .toggleArchive).isEmpty)
    }
}

// MARK: - Fixtures

private func item(
    _ packageName: String,
    title: String? = nil,
    favorite: Bool = false,
    archived: Bool = false
) -> GooglePlayAppItem {
    GooglePlayAppItem(
        id: packageName,
        packageName: packageName,
        title: title,
        isManuallyAdded: false,
        isFavorite: favorite,
        isArchived: archived
    )
}
