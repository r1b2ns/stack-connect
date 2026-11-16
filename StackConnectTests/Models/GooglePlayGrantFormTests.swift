import XCTest
@testable import StackConnect

/// The App Permissions sheet's rules (plan U7).
final class GooglePlayGrantFormTests: XCTestCase {

    private let reply = GooglePlayPermissionCatalog.all.first { $0.id == "replyToReviews" }!
    private let production = GooglePlayPermissionCatalog.all.first { $0.id == "releaseToProduction" }!
    private let view = GooglePlayPermissionCatalog.viewAppInformation

    func testAddingNeedsAnAppAndAPermission() {
        var form = GooglePlayGrantForm(packageName: nil, values: [], accountValues: [])
        XCTAssertFalse(form.isEditing)
        XCTAssertFalse(form.canSave)

        form.set(reply, isOn: true)
        XCTAssertFalse(form.canSave, "No app picked yet")
        form.packageName = "com.x.one"
        XCTAssertTrue(form.canSave)
        XCTAssertEqual(form.normalizedValues, ["CAN_VIEW_NON_FINANCIAL_DATA", "CAN_REPLY_TO_REVIEWS"])
    }

    func testViewAppInformationIsLockedOnWithAnyOtherPermission() {
        var form = GooglePlayGrantForm(packageName: "com.x.one", values: ["CAN_REPLY_TO_REVIEWS"], accountValues: [])
        XCTAssertTrue(form.isEditing)
        XCTAssertEqual(form.state(of: view), .implied)

        form.set(view, isOn: false)
        XCTAssertEqual(form.state(of: view), .implied, "Can't be turned off while another permission is on")
    }

    func testAccountWidePermissionsAreLockedOn() {
        var form = GooglePlayGrantForm(packageName: "com.x.one", values: [], accountValues: ["CAN_MANAGE_PUBLIC_APKS_GLOBAL"])

        XCTAssertEqual(form.state(of: production), .implied)
        form.set(production, isOn: false)
        XCTAssertEqual(form.state(of: production), .implied)
        XCTAssertEqual(form.state(of: reply), .off)
    }

    func testAdminLocksEverything() {
        let form = GooglePlayGrantForm(packageName: "com.x.one", values: [], accountValues: [GooglePlayPermissionCatalog.adminPermission])

        XCTAssertTrue(GooglePlayPermissionCatalog.appPermissions.allSatisfy { form.state(of: $0) == .implied })
    }

    func testUnknownValuesAreKept() {
        var form = GooglePlayGrantForm(packageName: "com.x.one", values: ["CAN_FUTURE_THING"], accountValues: [])

        form.set(reply, isOn: true)

        XCTAssertTrue(form.normalizedValues.contains("CAN_FUTURE_THING"))
    }
}
