import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class BetaGroupDetailViewModelTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var sut: BetaGroupDetailViewModel!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        sut = BetaGroupDetailViewModel(
            group: BetaGroupModel(
                id: "group-1",
                name: "QA",
                isInternalGroup: true,
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

    private let build = BuildModel(id: "build-1", version: "1")

    func testLoadTracksNothing() async {
        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testRefreshTracksFailureWithoutCredentials() async {
        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .betaGroupDetail, result: .failure)])
    }

    func testUpdateGroupTracksSaveTapAndFailure() async {
        await sut.updateGroup(name: "New", isPublicLinkEnabled: nil, publicLinkLimit: nil, isFeedbackEnabled: true)

        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .editBetaGroup)])
        XCTAssertEqual(analytics.actions(of: .updateBetaGroup), [.action(.updateBetaGroup, on: .editBetaGroup, result: .failure)])
    }

    func testAddBuildTracksOnlyTheOutcome() async {
        // The build row tap is tracked by the picker sheet, so no tap here.
        await sut.addBuildToGroup(buildId: build.id)

        XCTAssertTrue(analytics.trackedEvents.allSatisfy { $0.name == AnalyticsEventName.action })
        XCTAssertEqual(analytics.actions(of: .addBuildToGroup), [.action(.addBuildToGroup, on: .betaGroupDetail, result: .failure)])
    }

    func testBuildActionsTrackTapAndFailureWithoutCredentials() async {
        await sut.removeBuildFromGroup(build)
        await sut.expireBuild(build)

        XCTAssertEqual(analytics.taps(of: .confirmRemove), [.buttonTap(.confirmRemove, on: .betaGroupDetail)])
        XCTAssertEqual(analytics.taps(of: .confirmExpire), [.buttonTap(.confirmExpire, on: .betaGroupDetail)])
        XCTAssertEqual(analytics.results(of: .removeBuildFromGroup), [.failure])
        XCTAssertEqual(analytics.results(of: .expireBuild), [.failure])
    }

    func testConfirmSubmitTracksTapAndFailureWithoutCredentials() async {
        sut.uiState.submitSheetBuild = build

        await sut.confirmSubmitForReview(whatsNew: "Test the login flow")

        XCTAssertEqual(analytics.taps(of: .submitForReview), [.buttonTap(.submitForReview, on: .submitBuildForReview)])
        XCTAssertEqual(analytics.actions(of: .submitBuildForBetaReview), [
            .action(.submitBuildForBetaReview, on: .submitBuildForReview, result: .failure)
        ])
    }

    func testConfirmSubmitWithoutBuildTracksOnlyTheTap() async {
        await sut.confirmSubmitForReview(whatsNew: "Notes")

        XCTAssertEqual(analytics.taps(of: .submitForReview).count, 1)
        XCTAssertTrue(analytics.actions(of: .submitBuildForBetaReview).isEmpty)
    }
}
