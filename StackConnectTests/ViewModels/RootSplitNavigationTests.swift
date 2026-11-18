import Combine
import SwiftUI
import XCTest
@testable import StackConnect

// MARK: - Coordinator

@MainActor
final class RootSplitCoordinatorTests: XCTestCase {

    private var sut: RootSplitCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        sut = RootSplitCoordinator()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    private let account = AccountModel(id: "acc-1", name: "Northwind", providerType: .apple)

    func testStartsOnDashboardWithEmptyDetail() {
        XCTAssertEqual(sut.selection, .dashboard)
        XCTAssertNil(sut.detailRoute)
        XCTAssertTrue(sut.detailCoordinator.path.isEmpty)
    }

    func testDashboardUsesTwoColumnsAndListsUseThree() {
        XCTAssertFalse(RootSidebarItem.dashboard.usesContentColumn)
        XCTAssertTrue(RootSidebarItem.settings.usesContentColumn)
        XCTAssertTrue(RootSidebarItem.releaseQueue(.inReview).usesContentColumn)
        XCTAssertTrue(RootSidebarItem.account(id: "a", section: .apps).usesContentColumn)
        XCTAssertFalse(RootSidebarItem.account(id: "a", section: .users).usesContentColumn, "Users is a table + inspector")
    }

    func testContentColumnRoutesBecomeDetailRootInsteadOfPushing() {
        sut.select(.account(id: account.id, section: .apps), origin: .sidebar)

        sut.contentCoordinator.navigateToAppList(account)

        XCTAssertEqual(sut.detailRoute, .appList(account))
        XCTAssertTrue(sut.contentCoordinator.path.isEmpty, "The middle column never pushes")
    }

    func testPickingAnotherRowReplacesDetailAndDropsItsStack() {
        sut.select(.settings, origin: .sidebar)
        sut.contentCoordinator.navigateToLicense()
        sut.detailCoordinator.navigateToTipJar()
        XCTAssertEqual(sut.detailCoordinator.path.count, 1)

        sut.contentCoordinator.navigateToSettingsAccounts()

        XCTAssertEqual(sut.detailRoute, .settingsAccounts)
        XCTAssertTrue(sut.detailCoordinator.path.isEmpty)
    }

    func testDetailColumnPushesOnItsOwnStack() {
        sut.select(.settings, origin: .sidebar)
        sut.contentCoordinator.navigateToSettingsAccounts()

        sut.detailCoordinator.navigateToAccountsList(.apple)

        XCTAssertEqual(sut.detailRoute, .settingsAccounts)
        XCTAssertEqual(sut.detailCoordinator.path.count, 1)
    }

    func testSelectingAnItemClearsTheDetail() {
        sut.select(.settings, origin: .sidebar)
        sut.contentCoordinator.navigateToLicense()
        sut.detailCoordinator.navigateToTipJar()

        sut.select(.recentReviews, origin: .sidebar)

        XCTAssertEqual(sut.selection, .recentReviews)
        XCTAssertNil(sut.detailRoute)
        XCTAssertTrue(sut.detailCoordinator.path.isEmpty)
    }

    func testReselectingTheSameItemKeepsTheDetail() {
        sut.select(.settings, origin: .sidebar)
        sut.contentCoordinator.navigateToLicense()

        sut.select(.settings, origin: .sidebar)

        XCTAssertEqual(sut.detailRoute, .license)
    }

    func testPopToRootFromEitherColumnReturnsToDashboardAndReloadsAccounts() {
        sut.select(.account(id: account.id, section: .manage), origin: .sidebar)
        sut.contentCoordinator.navigateToLicense()
        let revision = sut.accountsRevision

        sut.contentCoordinator.popToRoot()

        XCTAssertEqual(sut.selection, .dashboard)
        XCTAssertNil(sut.detailRoute)
        XCTAssertEqual(sut.accountsRevision, revision + 1)

        sut.select(.settings, origin: .sidebar)
        sut.detailCoordinator.popToRoot()
        XCTAssertEqual(sut.selection, .dashboard)
        XCTAssertEqual(sut.accountsRevision, revision + 2)
    }

    // MARK: - Deep links

    func testDeepLinkRouteOpensOnTopOfTheDashboard() {
        sut.select(.settings, origin: .sidebar)

        sut.show(.appList(account))

        XCTAssertEqual(sut.selection, .dashboard)
        XCTAssertNil(sut.detailRoute)
        XCTAssertEqual(sut.detailCoordinator.path.count, 1)
    }

    func testDeepLinkReviewsSelectsRecentReviews() {
        sut.showAllReviews()
        XCTAssertEqual(sut.selection, .recentReviews)
    }

    func testDeepLinkHomeResetsToDashboard() {
        sut.show(.license)
        sut.showHome()
        XCTAssertEqual(sut.selection, .dashboard)
        XCTAssertTrue(sut.detailCoordinator.path.isEmpty)
    }

    // MARK: - Compact Home coordinator (unchanged behavior)

    func testPlainHomeCoordinatorStillPushesAndPopsToRoot() {
        let home = HomeCoordinator()
        home.navigateToSettings()
        home.navigateToLicense()
        XCTAssertEqual(home.path.count, 2)

        home.popToRoot()
        XCTAssertTrue(home.path.isEmpty)

        home.navigateToSettings()
        home.show(.license)
        XCTAssertEqual(home.path.count, 1)
    }

    // MARK: - Account sections

    func testAppStoreAccountWithFullRulesOffersEveryTeamTool() {
        XCTAssertEqual(
            RootAccountSection.sections(for: account),
            [.apps, .users, .devices, .certificates, .identifiers, .profiles, .manage]
        )
    }

    func testAppStoreAccountWithoutUsersOrProvisioningHidesThem() {
        let limited = AccountModel(
            name: "Limited",
            providerType: .apple,
            rules: AccountRules(apps: [.view], version: [.view])
        )
        XCTAssertEqual(RootAccountSection.sections(for: limited), [.apps, .manage])
    }

    func testOtherStoresOfferAppsAndManageOnly() {
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        let firebase = AccountModel(name: "Firebase", providerType: .firebase)
        XCTAssertEqual(RootAccountSection.sections(for: play), [.apps, .manage])
        XCTAssertEqual(RootAccountSection.sections(for: firebase), [.apps, .manage])
    }
}

// MARK: - Sidebar ViewModel

@MainActor
final class RootSidebarViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var trigger: PassthroughSubject<Void, Never>!
    private var sut: RootSidebarViewModel!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        trigger = PassthroughSubject()
        sut = RootSidebarViewModel(
            storage: storage,
            reloadTrigger: trigger.eraseToAnyPublisher(),
            queueCounter: { widget in widget.kind == .inReview ? 6 : 2 }
        )
    }

    override func tearDown() async throws {
        sut = nil
        trigger = nil
        storage = nil
        try await super.tearDown()
    }

    func testGroupsAccountsByStoreInSidebarOrderSortedByName() async throws {
        let accounts = [
            AccountModel(id: "1", name: "zeta", providerType: .apple),
            AccountModel(id: "2", name: "Alpha", providerType: .apple),
            AccountModel(id: "3", name: "fire", providerType: .firebase),
            AccountModel(id: "4", name: "play", providerType: .googlePlay)
        ]
        for account in accounts {
            try await storage.save(account, id: account.id)
        }

        await sut.load()

        let sections = sut.uiState.providerSections
        XCTAssertEqual(sections.map(\.provider), [.apple, .googlePlay, .firebase])
        XCTAssertEqual(sections[0].accounts.map(\.name), ["Alpha", "zeta"])
        XCTAssertEqual(sections[1].accounts.map(\.id), ["4"])
        XCTAssertEqual(sections[2].accounts.map(\.id), ["3"])
        XCTAssertTrue(sut.uiState.hasLoaded)
    }

    func testEmptyStorageKeepsOneEmptySectionPerStore() async {
        await sut.load()

        XCTAssertEqual(sut.uiState.providerSections.count, 3)
        XCTAssertTrue(sut.uiState.providerSections.allSatisfy { $0.accounts.isEmpty })
    }

    func testStorageFailureShowsNoAccountsWithoutCrashing() async {
        await storage.failFetchAll(AccountModel.self)

        await sut.load()

        XCTAssertTrue(sut.uiState.providerSections.allSatisfy { $0.accounts.isEmpty })
        XCTAssertTrue(sut.uiState.hasLoaded)
    }

    func testQueueCountsComeFromTheQueueWidgets() async {
        await sut.load()

        XCTAssertEqual(sut.uiState.queueCounts[.inReview], 6)
        XCTAssertEqual(sut.uiState.queueCounts[.awaitingRelease], 2)
        XCTAssertEqual(sut.widget(for: .inReview).kind, .inReview)
        XCTAssertEqual(sut.widget(for: .awaitingRelease).kind, .awaitingRelease)
    }

    func testAccountLookupById() async throws {
        let account = AccountModel(id: "acc", name: "Northwind", providerType: .googlePlay)
        try await storage.save(account, id: account.id)

        await sut.load()

        XCTAssertEqual(sut.account(id: "acc")?.name, "Northwind")
        XCTAssertNil(sut.account(id: "missing"))
    }

    func testReloadTriggerReloadsTheAccounts() async throws {
        await sut.load()
        let account = AccountModel(id: "new", name: "New", providerType: .apple)
        try await storage.save(account, id: account.id)

        let expectation = expectation(description: "reloaded")
        let cancellable = sut.$uiState
            .filter { $0.providerSections.first?.accounts.isEmpty == false }
            .first()
            .sink { _ in expectation.fulfill() }

        trigger.send(())

        await fulfillment(of: [expectation], timeout: 2)
        cancellable.cancel()
        XCTAssertNotNil(sut.account(id: "new"))
    }
}
