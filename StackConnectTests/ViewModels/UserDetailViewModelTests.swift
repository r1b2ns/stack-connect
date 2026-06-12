import XCTest
@testable import StackConnect

@MainActor
final class UserDetailViewModelTests: XCTestCase {

    func testPendingUserExposesExpirationDateAndRoles() {
        let expiration = Date(timeIntervalSince1970: 1_700_000_000)
        let user = UserModel(
            id: "invitation-1",
            firstName: "Ada",
            lastName: "Lovelace",
            email: "ada@example.com",
            roles: ["ADMIN", "DEVELOPER", "FINANCE"],
            allAppsVisible: true,
            provisioningAllowed: false,
            isPending: true,
            expirationDate: expiration
        )

        let sut = UserDetailViewModel(user: user)

        XCTAssertEqual(sut.uiState.user.roles.count, 3)
        XCTAssertTrue(sut.uiState.user.isPending)
        XCTAssertEqual(sut.uiState.user.expirationDate, expiration)
    }

    func testActiveUserHasNoExpirationDateAndIsNotPending() {
        let user = UserModel(
            id: "user-1",
            firstName: "Alan",
            lastName: "Turing",
            email: "alan@example.com",
            roles: ["DEVELOPER"],
            allAppsVisible: false,
            provisioningAllowed: true,
            isPending: false,
            expirationDate: nil
        )

        let sut = UserDetailViewModel(user: user)

        XCTAssertFalse(sut.uiState.user.isPending)
        XCTAssertNil(sut.uiState.user.expirationDate)
        XCTAssertEqual(sut.uiState.user.roles, ["DEVELOPER"])
    }
}
