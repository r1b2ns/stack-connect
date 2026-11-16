import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class TestFlightViewModelTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var sut: TestFlightViewModel!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        sut = TestFlightViewModel(
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

    private let group = BetaGroupModel(
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
    )

    func testLoadTracksNothing() async {
        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testRefreshTracksFailureWithoutCredentials() async {
        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .testFlight, result: .failure)])
    }

    func testCreateGroupTracksTapAndFailureWithGroupShapeOnly() async {
        await sut.createGroup(name: "Secret Group", isInternal: true, hasAccessToAllBuilds: true)

        XCTAssertEqual(analytics.taps(of: .create), [.buttonTap(.create, on: .createBetaGroup)])
        XCTAssertEqual(analytics.actions(of: .createBetaGroup), [
            .action(.createBetaGroup, on: .createBetaGroup, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("internal"),
                AnalyticsParameterKey.enabled: .bool(true)
            ])
        ])
    }

    func testDeleteAndExpireTrackTapAndFailureWithoutCredentials() async {
        await sut.deleteGroup(group)
        await sut.expireBuild(BuildModel(id: "build-1"))

        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .testFlight)])
        XCTAssertEqual(analytics.taps(of: .confirmExpire), [.buttonTap(.confirmExpire, on: .testFlight)])
        XCTAssertEqual(analytics.actions(of: .deleteBetaGroup), [.action(.deleteBetaGroup, on: .testFlight, result: .failure)])
        XCTAssertEqual(analytics.actions(of: .expireBuild), [.action(.expireBuild, on: .testFlight, result: .failure)])
    }
}
