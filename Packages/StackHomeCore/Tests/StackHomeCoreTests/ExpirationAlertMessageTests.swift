import XCTest
@testable import StackHomeCore

/// Pure-function tests for the shared expiration-alert message copy (US-005 /
/// TC-022). These cover the exact user-facing strings the iOS alert and the
/// Windows banner both render, so the copy is locked without a GUI.
final class ExpirationAlertMessageTests: XCTestCase {

    // MARK: - Expired copy (US-005 AC-1)

    func testExpiredMessageReproducesExactCopy() {
        let message = ExpirationAlertMessage.expired(accountName: "Acme")
        XCTAssertEqual(
            message,
            "The account \"Acme\" has expired. Re-import its file to keep using it, or it will stay locked."
        )
    }

    // MARK: - Expiring-soon copy (US-005 AC-4)

    func testExpiringSoonMessageWithDateIncludesFormattedDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = ExpirationAlertMessage.formattedExpiration(date)

        let message = ExpirationAlertMessage.expiringSoon(accountName: "Acme", expirationDate: date)

        XCTAssertEqual(
            message,
            "The account \"Acme\" will expire on \(expected). Request a new file from the administrator before then."
        )
        // The formatted date must actually appear in the rendered copy.
        XCTAssertTrue(message.contains(expected))
    }

    func testExpiringSoonMessageWithoutDateUsesFallbackCopy() {
        let message = ExpirationAlertMessage.expiringSoon(accountName: "Acme", expirationDate: nil)
        XCTAssertEqual(
            message,
            "The account \"Acme\" will expire soon. Request a new file from the administrator."
        )
    }
}
