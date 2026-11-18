import XCTest
@testable import StackConnect

final class GooglePlayTracksBoardTests: XCTestCase {

    private func track(_ name: String) -> GooglePlayTrackModel {
        GooglePlayTrackModel(track: name, releases: [])
    }

    func testColumnsFollowTheReleasePathFromInternalToProduction() {
        let tracks = [track("production"), track("beta"), track("qa-team"), track("alpha"), track("internal")]

        let columns = GooglePlayTracksBoard.columns(tracks).map(\.track)

        XCTAssertEqual(columns, ["internal", "alpha", "qa-team", "beta", "production"])
    }

    func testCustomTracksKeepTheirRelativeOrder() {
        let tracks = [track("zeta"), track("production"), track("alpha-2")]

        XCTAssertEqual(GooglePlayTracksBoard.columns(tracks).map(\.track), ["zeta", "alpha-2", "production"])
    }
}

final class UserAccessTableColumnTests: XCTestCase {

    private func user(pending: Bool, allApps: Bool) -> UserModel {
        UserModel(id: "u", firstName: "Priya", lastName: "Shah", email: "p@x", roles: ["DEVELOPER"],
                  allAppsVisible: allApps, provisioningAllowed: false, isPending: pending)
    }

    func testStatusColumnReflectsInvitationState() {
        XCTAssertEqual(user(pending: true, allApps: false).statusColumnText, String(localized: "Pending"))
        XCTAssertEqual(user(pending: false, allApps: false).statusColumnText, String(localized: "Active"))
    }

    func testAppsColumnSaysAllAppsOnlyWhenVisible() {
        XCTAssertEqual(user(pending: false, allApps: true).appsColumnText, String(localized: "All Apps"))
        XCTAssertEqual(user(pending: false, allApps: false).appsColumnText, "–")
    }
}
