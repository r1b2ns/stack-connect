import XCTest
import StackCoreRust
@testable import StackConnect

final class GooglePlayErrorTranslatorTests: XCTestCase {

    private func message(for error: Error) -> String {
        GooglePlayErrorTranslator.friendlyMessage(for: error)
    }

    // MARK: - Local errors

    func testParseErrorUsesItsOwnCopy() {
        let error = GooglePlayServiceAccount.ParseError.missingField(.clientEmail)
        XCTAssertEqual(message(for: error), error.localizedDescription)
    }

    func testOfflineGuardUsesTheSharedOfflineCopy() {
        XCTAssertEqual(message(for: OfflineError.noConnection), OfflineError.noConnection.localizedDescription)
        XCTAssertTrue(GooglePlayErrorTranslator.isOffline(OfflineError.noConnection))
    }

    func testUnknownErrorFallsBackToItsDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Boom"])
        XCTAssertEqual(message(for: error), "Boom")
        XCTAssertFalse(GooglePlayErrorTranslator.isOffline(error))
    }

    // MARK: - StackError

    func testInvalidCredentialsHidesTheCoreDetail() {
        let text = message(for: StackError.InvalidCredentials(message: "ASN.1 parse error at byte 12"))

        XCTAssertEqual(text, String(localized: "The service account key is invalid. Download a new JSON key from Google Cloud and try again."))
        XCTAssertFalse(text.contains("ASN.1"))
    }

    func testAuthKeepsTheCoresActionableDetailAfterALocalizedLead() {
        let detail = "Google Play Developer Reporting API has not been used in project 123 before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/playdeveloperreporting.googleapis.com/overview?project=123"

        let text = message(for: StackError.Auth(message: "  \(detail)\n"))

        XCTAssertEqual(text, String(localized: "Google Play denied access to this service account.") + "\n" + detail)
    }

    func testAuthWithoutDetailShowsOnlyTheLead() {
        XCTAssertEqual(
            message(for: StackError.Auth(message: "   ")),
            String(localized: "Google Play denied access to this service account.")
        )
    }

    func testNetworkErrorIsTreatedAsOffline() {
        let error = StackError.Network(message: "error sending request: connection refused")

        XCTAssertEqual(message(for: error), String(localized: "Couldn't reach Google Play. Check your internet connection and try again."))
        XCTAssertTrue(GooglePlayErrorTranslator.isOffline(error))
    }

    func testRateLimit() {
        XCTAssertEqual(
            message(for: StackError.Http(status: 429, message: "RESOURCE_EXHAUSTED")),
            String(localized: "You hit Google's rate limit. Wait a moment and try again.")
        )
    }

    func testServerErrors() {
        let expected = String(localized: "Google Play is temporarily unavailable. Try again in a few minutes.")
        XCTAssertEqual(message(for: StackError.Http(status: 500, message: "")), expected)
        XCTAssertEqual(message(for: StackError.Http(status: 503, message: "")), expected)
        XCTAssertFalse(GooglePlayErrorTranslator.isOffline(StackError.Http(status: 503, message: "")))
    }

    func testOtherHttpStatusIsGenericWithTheStatus() {
        let text = message(for: StackError.Http(status: 404, message: "{\"error\": {\"status\": \"NOT_FOUND\"}}"))

        XCTAssertEqual(text, String(localized: "Google Play returned an unexpected error (HTTP \(404))."))
        XCTAssertFalse(text.contains("NOT_FOUND"), "The raw body must not be shown")
    }

    func testDecodeAndUnsupported() {
        XCTAssertEqual(
            message(for: StackError.Decode(message: "missing field `apps`")),
            String(localized: "Google Play returned an unexpected response. Try again later.")
        )
        XCTAssertEqual(
            message(for: StackError.Unsupported(message: "reviews")),
            String(localized: "This action isn't available for Google Play accounts yet.")
        )
    }

    func testAppStoreOnlyCasesFallBackToGenericCopy() {
        let generic = String(localized: "Something went wrong while talking to Google Play. Try again.")
        XCTAssertEqual(message(for: StackError.PendingAgreements(message: "x")), generic)
        XCTAssertEqual(message(for: StackError.SubmissionNotRemovable(message: "x")), generic)
    }

    func testStackErrorDebugDescriptionIsNeverShownRaw() {
        let errors: [StackError] = [
            .InvalidCredentials(message: "a"), .Auth(message: "b"), .PendingAgreements(message: "c"),
            .Http(status: 418, message: "d"), .Decode(message: "e"), .Network(message: "f"),
            .Unsupported(message: "g"), .SubmissionNotRemovable(message: "h")
        ]
        for error in errors {
            XCTAssertFalse(message(for: error).contains("StackError"), "\(error) leaked its debug description")
        }
    }
}
