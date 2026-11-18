import Combine
import StackProtocols
import SwiftUI
import XCTest
@testable import StackConnect

/// Analytics of the iPad / Mac split view: sidebar navigation and menu
/// commands, the release queue screens, the Reviews inbox filter and the
/// `ui_layout` user property.
@MainActor
final class RootSplitAnalyticsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - Navigation

    func testSidebarSelectionSendsOneNavigateActionWithKindAndOrigin() {
        let sut = RootSplitCoordinator(analytics: analytics)

        sut.select(.recentReviews, origin: .sidebar)

        XCTAssertEqual(analytics.trackedEvents, [
            AnalyticsEvent(name: "action", parameters: [
                "action_name": .string("navigate"),
                "destination": .string("recent_reviews"),
                "source": .string("sidebar")
            ])
        ], "No screen_name, no account data")
    }

    func testEachOriginIsReported() {
        let sut = RootSplitCoordinator(analytics: analytics)

        sut.select(.settings, origin: .sidebar)
        sut.select(.releaseQueue(.inReview), origin: .dashboardTile)
        sut.select(RootNavigationShortcut.awaitingRelease.item, origin: .menuCommand)

        XCTAssertEqual(sources(), ["sidebar", "dashboard_tile", "menu_command"])
        XCTAssertEqual(destinations(), ["settings", "release_queue_in_review", "release_queue_awaiting_release"])
    }

    func testReselectingTheCurrentItemSendsNothing() {
        let sut = RootSplitCoordinator(analytics: analytics)

        sut.select(.dashboard, origin: .menuCommand)
        sut.select(.settings, origin: .sidebar)
        sut.select(.settings, origin: .menuCommand)

        XCTAssertEqual(analytics.actions(of: .navigate).count, 1)
    }

    func testAccountItemsReportTheTeamToolOnlyNeverTheAccount() {
        let sut = RootSplitCoordinator(analytics: analytics)

        sut.select(.account(id: "secret-account-id", section: .apps), origin: .sidebar)
        sut.select(.account(id: "secret-account-id", section: .users), origin: .sidebar)
        sut.select(.addAccount(.googlePlay), origin: .sidebar)
        sut.select(.addAccount(.apple), origin: .menuCommand)

        XCTAssertEqual(destinations(), ["account_apps", "account_users", "add_account", "add_account"])
        let values = analytics.trackedEvents.flatMap(\.parameters.values)
        XCTAssertFalse(values.contains(.string("secret-account-id")))
    }

    func testProgrammaticMovesAreNotNavigation() {
        let sut = RootSplitCoordinator(analytics: analytics)
        sut.select(.settings, origin: .sidebar)

        sut.showAllReviews()
        sut.showHome()
        sut.returnToDashboard()

        XCTAssertEqual(analytics.actions(of: .navigate).count, 1, "Deep links and pop to root are not user navigation")
    }

    func testEverySidebarItemKindMapsToADestination() {
        let items: [RootSidebarItem] = [.dashboard, .releaseQueue(.inReview), .releaseQueue(.awaitingRelease), .recentReviews]
            + RootAccountSection.allCases.map { .account(id: "a", section: $0) }
            + [.addAccount(.firebase), .settings]

        let destinations = Set(items.map(AnalyticsSidebarDestination.init))

        XCTAssertEqual(destinations, Set(AnalyticsSidebarDestination.allCases))
    }

    // MARK: - Menu commands

    func testFindCommandIsTrackedFromTheMenu() {
        let sut = RootSplitCoordinator(analytics: analytics)

        sut.requestSearch()

        XCTAssertEqual(analytics.trackedEvents, [
            AnalyticsEvent(name: "action", parameters: [
                "action_name": .string("find"),
                "source": .string("menu_command")
            ])
        ])
    }

    func testRefreshCommandTracksAScreenlessRefreshWithItsOutcome() async {
        let syncService = SyncService(storage: MockPersistentStorable(), keychain: MockKeyStorable(), analytics: MockAnalyticsTracker())

        await AppMenuRefresh.perform(syncService: syncService, analytics: analytics)

        let refresh = analytics.actions(of: .refresh)
        XCTAssertEqual(refresh.count, 1)
        XCTAssertEqual(analytics.results(of: .refresh), [.success])
        XCTAssertEqual(refresh.first?.parameters["source"], .string("menu_command"))
        XCTAssertNil(refresh.first?.parameters["screen_name"])
    }

    // MARK: - Release queues

    func testEachQueueHasItsOwnScreen() {
        XCTAssertEqual(RootReleaseQueue.inReview.analyticsScreen.rawValue, "release_queue_in_review")
        XCTAssertEqual(RootReleaseQueue.awaitingRelease.analyticsScreen.rawValue, "release_queue_awaiting_release")
    }

    func testQueueRefreshIsTrackedOnTheQueueScreen() async {
        let sut = makeSidebarViewModel(storage: MockPersistentStorable())

        await sut.refresh(.awaitingRelease)

        let refresh = analytics.actions(of: .refresh)
        XCTAssertEqual(refresh.count, 1)
        XCTAssertEqual(refresh.first?.parameters["screen_name"], .string("release_queue_awaiting_release"))
        XCTAssertEqual(analytics.results(of: .refresh), [.success])
    }

    func testQueueRefreshFailsWhenAccountsCannotBeRead() async {
        let storage = MockPersistentStorable()
        await storage.failFetchAll(AccountModel.self)
        let sut = makeSidebarViewModel(storage: storage)

        await sut.refresh(.inReview)

        XCTAssertEqual(analytics.results(of: .refresh), [.failure])
    }

    func testPlainSidebarReloadIsNotARefresh() async {
        let sut = makeSidebarViewModel(storage: MockPersistentStorable())

        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    // MARK: - Widgets on several screens

    func testWidgetTapsReportTheTrackedScreenAroundThem() {
        XCTAssertEqual(
            StackTrackedButton<Text>.resolvedScreen(environment: .releaseQueueInReview, fallback: .home),
            .releaseQueueInReview
        )
        XCTAssertEqual(StackTrackedButton<Text>.resolvedScreen(environment: nil, fallback: .home), .home)
    }

    // MARK: - Reviews inbox filter

    func testInboxFilterChangeIsTrackedWithTheFilterKind() {
        let sut = AllReviewsViewModel(storage: MockPersistentStorable(), analytics: analytics)

        sut.applyFilter(.googlePlay)
        sut.applyFilter(.unreplied)

        XCTAssertEqual(sut.uiState.filter, .unreplied)
        XCTAssertEqual(analytics.actions(of: .filterReviews).map { $0.parameters["kind"] }, [
            .string("google_play"), .string("unreplied")
        ])
        XCTAssertEqual(analytics.actions(of: .filterReviews).first?.parameters["screen_name"], .string("all_reviews"))
    }

    func testPickingTheShownFilterSendsNothing() {
        let sut = AllReviewsViewModel(storage: MockPersistentStorable(), analytics: analytics)

        sut.applyFilter(.all)

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testReviewsFilterMapsEveryCase() {
        XCTAssertEqual(AllReviewsFilter.allCases.map { AnalyticsReviewsFilter($0).rawValue },
                       ["all", "app_store", "google_play", "unreplied"])
    }

    // MARK: - ui_layout

    func testLayoutFollowsTheHorizontalSizeClass() {
        XCTAssertEqual(AppRootView.layout(for: .regular), .regular)
        XCTAssertEqual(AppRootView.layout(for: .compact), .compact)
        XCTAssertEqual(AppRootView.layout(for: nil), .compact, "Anything but regular shows the iPhone Home")
    }

    func testLayoutIsSetAsAUserProperty() {
        AppRootView.reportLayout(for: .regular, to: analytics)
        AppRootView.reportLayout(for: .compact, to: analytics)

        XCTAssertEqual(analytics.userPropertyUpdates, [[.uiLayout: "regular"], [.uiLayout: "compact"]])
    }

    func testLayoutPropertyIsOnlySentWhenItChangesAndRespectsTheOptOut() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RootSplitAnalyticsTests.\(UUID().uuidString)"))
        let provider = MockAnalyticsProvider()
        let service = AnalyticsService(providers: [provider], settings: AppSettings(defaults: defaults))

        AppRootView.reportLayout(for: .regular, to: service)
        AppRootView.reportLayout(for: .regular, to: service)
        AppRootView.reportLayout(for: .compact, to: service)
        service.setEnabled(false)
        AppRootView.reportLayout(for: .regular, to: service)

        XCTAssertEqual(provider.userPropertyCalls.map(\.name), ["ui_layout", "ui_layout"])
        XCTAssertEqual(provider.userPropertyCalls.map(\.value), ["regular", "compact"])
    }

    // MARK: - Helpers

    private func makeSidebarViewModel(storage: MockPersistentStorable) -> RootSidebarViewModel {
        RootSidebarViewModel(
            storage: storage,
            reloadTrigger: Empty().eraseToAnyPublisher(),
            queueCounter: { _ in 0 },
            analytics: analytics
        )
    }

    private func sources() -> [String] {
        analytics.actions(of: .navigate).compactMap {
            if case .string(let raw)? = $0.parameters["source"] { return raw }
            return nil
        }
    }

    private func destinations() -> [String] {
        analytics.actions(of: .navigate).compactMap {
            if case .string(let raw)? = $0.parameters["destination"] { return raw }
            return nil
        }
    }
}
