import SwiftUI
import StackProtocols
import XCTest
@testable import StackConnect

/// The compact-width root: Accounts / Settings tabs, their stacks, deep links
/// and the tab bar `navigate` action.
@MainActor
final class RootTabCoordinatorTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var sut: RootTabCoordinator!

    private let account = AccountModel(id: "acc-1", name: "Northwind", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        sut = RootTabCoordinator(analytics: analytics)
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - Tabs

    func testStartsOnAccountsWithEmptyStacks() {
        XCTAssertEqual(sut.selection, .accounts)
        XCTAssertTrue(sut.accountsCoordinator.path.isEmpty)
        XCTAssertTrue(sut.settingsCoordinator.path.isEmpty)
        XCTAssertFalse(sut.accountsCoordinator === sut.settingsCoordinator, "Each tab has its own stack")
    }

    func testTabsKeepTheirOwnStacks() {
        sut.accountsCoordinator.navigateToAccountsList(.apple)
        sut.select(.settings)
        sut.settingsCoordinator.navigateToSettingsAccounts()
        sut.settingsCoordinator.navigateToLicense()

        XCTAssertEqual(sut.selection, .settings)
        XCTAssertEqual(sut.accountsCoordinator.path.count, 1)
        XCTAssertEqual(sut.settingsCoordinator.path.count, 2)

        sut.select(.accounts)
        XCTAssertEqual(sut.accountsCoordinator.path.count, 1, "Switching tabs keeps each stack")
        XCTAssertEqual(sut.settingsCoordinator.path.count, 2)
    }

    func testTabsHaveTitlesAndSymbols() {
        XCTAssertEqual(RootTab.allCases, [.accounts, .settings])
        XCTAssertEqual(RootTab.settings.systemImage, "gearshape")
        for tab in RootTab.allCases {
            XCTAssertFalse(tab.title.isEmpty)
            XCTAssertFalse(tab.systemImage.isEmpty)
        }
    }

    // MARK: - Pop to root

    func testPopToRootFromSettingsUnwindsBothStacks() {
        sut.accountsCoordinator.navigateToAccountsList(.apple)
        sut.accountsCoordinator.navigateToAppList(account)
        sut.select(.settings)
        sut.settingsCoordinator.navigateToSettingsAccounts()
        sut.settingsCoordinator.navigateToAccountSettings(account)

        // Delete All Accounts / deleting an account from Settings.
        sut.settingsCoordinator.popToRoot()

        XCTAssertTrue(sut.settingsCoordinator.path.isEmpty)
        XCTAssertTrue(sut.accountsCoordinator.path.isEmpty, "No tab keeps screens of a deleted account")
        XCTAssertEqual(sut.selection, .settings, "Stays on the tab the user is on")
    }

    func testPopToRootFromAccountsUnwindsBothStacks() {
        sut.settingsCoordinator.navigateToSettingsAccounts()
        sut.accountsCoordinator.navigateToAccountManagement(account)

        sut.accountsCoordinator.popToRoot()

        XCTAssertTrue(sut.accountsCoordinator.path.isEmpty)
        XCTAssertTrue(sut.settingsCoordinator.path.isEmpty)
    }

    // MARK: - Deep links

    func testDeepLinkRouteSwitchesToAccountsAndOpensOnTopOfHome() {
        sut.select(.settings)
        sut.accountsCoordinator.navigateToLicense()
        sut.settingsCoordinator.navigateToSettingsAccounts()

        sut.show(.appList(account))

        XCTAssertEqual(sut.selection, .accounts)
        XCTAssertEqual(sut.accountsCoordinator.path.count, 1)
        XCTAssertEqual(sut.settingsCoordinator.path.count, 1, "The Settings stack is left alone")
    }

    func testDeepLinkReviewsSwitchesToAccounts() {
        sut.select(.settings)

        sut.showAllReviews()

        XCTAssertEqual(sut.selection, .accounts)
        XCTAssertEqual(sut.accountsCoordinator.path.count, 1)
    }

    func testDeepLinkHomeSwitchesToAccountsRoot() {
        sut.accountsCoordinator.navigateToAccountsList(.firebase)
        sut.select(.settings)

        sut.showHome()

        XCTAssertEqual(sut.selection, .accounts)
        XCTAssertTrue(sut.accountsCoordinator.path.isEmpty)
    }

    func testDeepLinkHandlerRoutesHomeAndReviewsThroughTheTabs() throws {
        let handler = HomeDeepLinkHandler(navigator: sut, storage: nil)
        sut.select(.settings)

        handler.handle(try XCTUnwrap(URL(string: "stackconnect://reviews")))
        XCTAssertEqual(sut.selection, .accounts)
        XCTAssertEqual(sut.accountsCoordinator.path.count, 1)

        sut.select(.settings)
        handler.handle(try XCTUnwrap(URL(string: "stackconnect://home")))
        XCTAssertEqual(sut.selection, .accounts)
        XCTAssertTrue(sut.accountsCoordinator.path.isEmpty)
    }

    // MARK: - Analytics

    func testTabSelectionSendsOneNavigateActionWithTabBarOrigin() {
        sut.select(.settings)

        XCTAssertEqual(analytics.trackedEvents, [
            AnalyticsEvent(name: "action", parameters: [
                "action_name": .string("navigate"),
                "destination": .string("settings"),
                "source": .string("tab_bar")
            ])
        ], "No screen_name, no account data")

        sut.select(.accounts)
        XCTAssertEqual(analytics.actions(of: .navigate).last?.parameters["destination"], .string("dashboard"))
    }

    func testReselectingAndDeepLinksAreNotTracked() {
        sut.select(.accounts)
        sut.show(.license)
        sut.showAllReviews()
        sut.showHome()
        sut.settingsCoordinator.popToRoot()

        XCTAssertTrue(analytics.actions(of: .navigate).isEmpty)
    }
}
