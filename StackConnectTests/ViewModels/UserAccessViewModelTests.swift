import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class UserAccessViewModelTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var sut: UserAccessViewModel!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        sut = UserAccessViewModel(
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

    private func makeUser(isPending: Bool) -> UserModel {
        UserModel(
            id: "user-1",
            firstName: "Ada",
            lastName: "Lovelace",
            email: "ada@example.com",
            roles: ["DEVELOPER"],
            allAppsVisible: true,
            provisioningAllowed: false,
            isPending: isPending,
            expirationDate: nil
        )
    }

    func testLoadTracksNothing() async {
        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testRefreshTracksFailureWithoutCredentials() async {
        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .userAccess, result: .failure)])
    }

    func testDeleteTracksTapAndKindOnly() async {
        await sut.deleteUser(makeUser(isPending: false))
        await sut.deleteUser(makeUser(isPending: true))

        XCTAssertEqual(analytics.taps(of: .confirmDelete).count, 2)
        XCTAssertEqual(analytics.actions(of: .deleteUser), [
            .action(.deleteUser, on: .userAccess, result: .failure, parameters: [AnalyticsParameterKey.kind: .string("member")]),
            .action(.deleteUser, on: .userAccess, result: .failure, parameters: [AnalyticsParameterKey.kind: .string("invitation")])
        ])
    }

    func testInviteTracksTapAndInvitationShapeWithoutPII() async {
        await sut.inviteUser(
            email: "ada@example.com",
            firstName: "Ada",
            lastName: "Lovelace",
            roles: ["DEVELOPER", "MARKETING"],
            allAppsVisible: false,
            provisioningAllowed: true
        )

        XCTAssertEqual(analytics.taps(of: .invite), [.buttonTap(.invite, on: .inviteUser)])
        XCTAssertEqual(analytics.actions(of: .inviteUser), [
            .action(.inviteUser, on: .inviteUser, result: .failure, parameters: [
                AnalyticsParameterKey.count: .int(2),
                AnalyticsParameterKey.scoped: .bool(true)
            ])
        ])
    }
}
