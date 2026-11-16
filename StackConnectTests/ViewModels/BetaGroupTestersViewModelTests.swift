import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class BetaGroupTestersViewModelTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var sut: BetaGroupTestersViewModel!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        sut = BetaGroupTestersViewModel(
            group: BetaGroupModel(
                id: "group-1",
                name: "QA",
                isInternalGroup: false,
                createdDate: nil,
                hasAccessToAllBuilds: false,
                isPublicLinkEnabled: false,
                publicLink: nil,
                publicLinkId: nil,
                publicLinkLimit: nil,
                isPublicLinkLimitEnabled: false,
                isFeedbackEnabled: true,
                testerCount: nil,
                buildCount: nil
            ),
            appId: "app-1",
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
        try await super.tearDown()
    }

    private let tester = BetaTesterModel(
        id: "tester-1",
        firstName: "Ada",
        lastName: "Lovelace",
        email: "ada@example.com",
        inviteType: "EMAIL",
        state: "INVITED"
    )

    func testLoadTracksNothing() async {
        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testRefreshTracksFailureWithoutCredentials() async {
        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .betaGroupTesters, result: .failure)])
    }

    func testAddTesterTracksInviteTapAndFailureWithoutPII() async {
        await sut.addTester(email: "ada@example.com", firstName: "Ada", lastName: nil)

        XCTAssertEqual(analytics.taps(of: .invite), [.buttonTap(.invite, on: .addTester)])
        XCTAssertEqual(analytics.actions(of: .inviteTester), [.action(.inviteTester, on: .addTester, result: .failure)])
    }

    func testImportCSVTracksContinueTapAndRowCount() async {
        let rows = [
            CSVTesterRow(firstName: "A", lastName: "B", email: "a@example.com"),
            CSVTesterRow(firstName: "C", lastName: "D", email: "c@example.com")
        ]

        await sut.importCSVTesters(rows)

        XCTAssertEqual(analytics.taps(of: .continue), [.buttonTap(.continue, on: .csvTesterImport)])
        XCTAssertEqual(analytics.actions(of: .importTesters), [
            .action(.importTesters, on: .csvTesterImport, result: .failure, parameters: [
                AnalyticsParameterKey.count: .int(2)
            ])
        ])
    }

    func testImportEmptyCSVTracksOnlyTheTap() async {
        await sut.importCSVTesters([])

        XCTAssertEqual(analytics.taps(of: .continue).count, 1)
        XCTAssertTrue(analytics.actions(of: .importTesters).isEmpty)
    }

    func testInviteTeamMembersTracksTapAndMemberCount() async {
        let members = [TeamMemberModel(id: "m-1", firstName: "A", lastName: "B", username: "a@example.com", roles: ["DEVELOPER"])]

        await sut.addTeamMembersAsTesters(members)

        XCTAssertEqual(analytics.taps(of: .invite), [.buttonTap(.invite, on: .internalTesterPicker)])
        XCTAssertEqual(analytics.actions(of: .inviteTesters), [
            .action(.inviteTesters, on: .internalTesterPicker, result: .failure, parameters: [
                AnalyticsParameterKey.count: .int(1)
            ])
        ])
    }

    func testRemoveAndResendTrackTapAndFailureWithoutCredentials() async {
        await sut.removeTester(tester)
        await sut.resendInvite(tester)

        XCTAssertEqual(analytics.taps(of: .confirmRemove), [.buttonTap(.confirmRemove, on: .betaGroupTesters)])
        XCTAssertEqual(analytics.taps(of: .resendInvite), [.buttonTap(.resendInvite, on: .betaGroupTesters)])
        XCTAssertEqual(analytics.results(of: .removeTester), [.failure])
        XCTAssertEqual(analytics.results(of: .resendInvite), [.failure])
    }
}
