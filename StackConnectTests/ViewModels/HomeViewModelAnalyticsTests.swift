import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics events sent by `HomeViewModel` (agreements banner and widget customisation).
@MainActor
final class HomeViewModelAnalyticsTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var analytics: MockAnalyticsTracker!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        storage = nil
        try await super.tearDown()
    }

    private func makeSUT(fetcher: (any TeamUsersFetching)? = nil) -> HomeViewModel {
        HomeViewModel(
            storage: storage,
            keychain: MockKeyStorable(),
            preferences: MockKeyStorable(),
            syncService: .shared,
            teamUsersFetcherFactory: { _ in fetcher },
            analytics: analytics
        )
    }

    private func makeFlaggedAccount() async throws -> AccountModel {
        let account = AccountModel(
            id: "acc-1",
            name: "Team",
            providerType: .apple,
            hasPendingAgreements: true,
            pendingAgreementsDetectedAt: .now
        )
        try await storage.save(account, id: account.id)
        return account
    }

    // MARK: - Widgets

    func testAddWidgetTracksTheWidgetKind() {
        let sut = makeSUT()

        sut.addWidget(.inReview)

        XCTAssertEqual(analytics.actions(of: .addWidget), [
            .action(.addWidget, on: .customizeWidgets, parameters: [AnalyticsParameterKey.kind: .string("inReview")])
        ])
    }

    func testAddingAnExistingWidgetTracksNothing() {
        let sut = makeSUT()
        sut.addWidget(.inReview)

        sut.addWidget(.inReview)

        XCTAssertEqual(analytics.actions(of: .addWidget).count, 1)
    }

    func testRemoveWidgetTracksTheWidgetKind() throws {
        let sut = makeSUT()
        sut.addWidget(.recentReviews)
        let id = try XCTUnwrap(sut.uiState.widgets.first { $0.kind == .recentReviews }?.id)

        sut.removeWidget(id: id)

        XCTAssertEqual(analytics.actions(of: .removeWidget), [
            .action(.removeWidget, on: .customizeWidgets, parameters: [AnalyticsParameterKey.kind: .string("recentReviews")])
        ])
    }

    func testMoveWidgetsTracksReorder() {
        let sut = makeSUT()
        sut.addWidget(.inReview)
        sut.addWidget(.awaitingRelease)

        sut.moveWidgets(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(analytics.actions(of: .reorderWidgets), [.action(.reorderWidgets, on: .customizeWidgets)])
    }

    // MARK: - Agreements banner

    func testDismissAgreementsBannerTracksTap() async throws {
        let account = try await makeFlaggedAccount()
        let sut = makeSUT()
        await sut.loadDashboard()

        sut.dismissPendingAgreements(accountId: account.id)

        XCTAssertEqual(analytics.taps(of: .dismissAgreementsBanner), [.buttonTap(.dismissAgreementsBanner, on: .home)])
    }

    func testShareAgreementsTracksTapAndSuccessWithAccountHolder() async throws {
        let account = try await makeFlaggedAccount()
        let holder = UserModel(
            id: "holder", firstName: "Jane", lastName: "Doe", email: "jane@example.com",
            roles: [UserRoleCatalog.accountHolder], allAppsVisible: true,
            provisioningAllowed: false, isPending: false, expirationDate: nil
        )
        let sut = makeSUT(fetcher: MockTeamUsersFetcher(users: [holder]))
        await sut.loadDashboard()

        await sut.prepareAgreementShare(accountId: account.id)

        XCTAssertEqual(analytics.taps(of: .shareAgreementsRequest), [.buttonTap(.shareAgreementsRequest, on: .home)])
        XCTAssertEqual(analytics.actions(of: .shareAgreementsRequest), [
            .action(.shareAgreementsRequest, on: .home, result: .success, parameters: [
                AnalyticsParameterKey.hasAccountHolder: .bool(true)
            ])
        ])
    }

    func testShareAgreementsWithoutAccountHolderTracksFallback() async throws {
        let account = try await makeFlaggedAccount()
        let sut = makeSUT(fetcher: nil)
        await sut.loadDashboard()

        await sut.prepareAgreementShare(accountId: account.id)

        XCTAssertEqual(analytics.actions(of: .shareAgreementsRequest).first?.parameters[AnalyticsParameterKey.hasAccountHolder], .bool(false))
    }
}
