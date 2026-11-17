import XCTest
@testable import StackConnect

/// The Invite User sheet's rules (plan U6, U5 presets).
final class GooglePlayInviteFormTests: XCTestCase {

    private let reply = GooglePlayPermissionCatalog.all.first { $0.id == "replyToReviews" }!
    private let orders = GooglePlayPermissionCatalog.all.first { $0.id == "orders" }!

    func testEmailValidation() {
        var form = GooglePlayInviteForm()
        form.apply(.support)

        form.email = "dele@agency"
        XCTAssertFalse(form.canSend)
        XCTAssertNotNil(form.blockingReason)
        form.email = "  dele@agency.example "
        XCTAssertTrue(form.canSend)
        XCTAssertEqual(form.trimmedEmail, "dele@agency.example")
    }

    func testSomethingMustBeGranted() {
        var form = GooglePlayInviteForm()
        form.email = "a@b.example"
        XCTAssertFalse(form.canSend)

        form.setGrant(packageName: "com.x.one", values: ["CAN_REPLY_TO_REVIEWS"])
        XCTAssertTrue(form.canSend)
        XCTAssertEqual(form.grants.first?.appLevelPermissions, ["CAN_VIEW_NON_FINANCIAL_DATA", "CAN_REPLY_TO_REVIEWS"])
        form.removeGrant(packageName: "com.x.one")
        XCTAssertFalse(form.canSend)
    }

    func testPresetsPrefillAndManualChangesSelectTheMatchingPreset() {
        var form = GooglePlayInviteForm()
        XCTAssertEqual(form.preset, .custom)

        form.apply(.finance)
        XCTAssertEqual(Set(form.accountPermissions), ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_VIEW_FINANCIAL_DATA_GLOBAL", "CAN_MANAGE_ORDERS_GLOBAL"])
        form.set(orders, isOn: false)
        XCTAssertEqual(form.preset, .custom, "A change away from the preset is Custom")

        form.apply(.custom)
        XCTAssertFalse(form.accountPermissions.contains("CAN_MANAGE_ORDERS_GLOBAL"), "Custom keeps the toggles")

        form.apply(.admin)
        XCTAssertTrue(form.isAdmin)
        XCTAssertEqual(form.accountState(of: reply), .implied)
        form.setAdmin(false)
        form.set(reply, isOn: true)
        XCTAssertEqual(form.preset, .support, "Reply to reviews (+ view) is the Support preset")
    }
}
