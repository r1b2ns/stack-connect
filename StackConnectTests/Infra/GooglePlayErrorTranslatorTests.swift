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
        let text = message(for: StackError.Http(status: 418, message: "{\"error\": {\"status\": \"TEAPOT\"}}"))

        XCTAssertEqual(text, String(localized: "Google Play returned an unexpected error (HTTP \(418))."))
        XCTAssertFalse(text.contains("TEAPOT"), "The raw body must not be shown")
    }

    func testDecodeAndUnsupported() {
        XCTAssertEqual(
            message(for: StackError.Decode(message: "missing field `apps`")),
            String(localized: "Google Play returned an unexpected response. Try again later.")
        )
        XCTAssertEqual(
            message(for: StackError.Unsupported(message: "delete_review_response")),
            String(localized: "Google Play doesn't support this action.")
        )
    }

    // MARK: - App content and reviews (Phase 3)

    func testNotFoundMeansUnknownPackage() {
        let text = message(for: StackError.Http(status: 404, message: "Google Play found no app with package name com.nope"))

        XCTAssertEqual(text, String(localized: "Google Play found no app with this package name. Check it in Play Console and try again."))
        XCTAssertFalse(text.contains("com.nope"), "The raw core message must not be shown")
    }

    /// A reply 404 is a review Google no longer shares, not a missing app.
    func testNotFoundOnAReplyMeansTheReviewIsGone() {
        let text = GooglePlayErrorTranslator.friendlyMessage(
            for: StackError.Http(status: 404, message: "Review not found"),
            operation: .replyToReview
        )

        XCTAssertEqual(text, String(localized: "This review is no longer available on Google Play."))
    }

    /// An edit-based read 404 can be an edit invalidated by another one.
    func testNotFoundOnAnEditReadIsAGenericLoadFailure() {
        let text = GooglePlayErrorTranslator.friendlyMessage(
            for: StackError.Http(status: 404, message: "Edit not found"),
            operation: .appContentRead
        )

        XCTAssertEqual(text, String(localized: "Google Play couldn't load this information. Try again in a moment."))
        XCTAssertNotEqual(text, message(for: StackError.Http(status: 404, message: "")))
    }

    func testOtherStatusesKeepTheirCopyWhateverTheOperation() {
        for operation in [GooglePlayErrorTranslator.Operation.general, .appContentRead, .replyToReview] {
            XCTAssertEqual(
                GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 429, message: ""), operation: operation),
                String(localized: "You hit Google's rate limit. Wait a moment and try again."),
                "\(operation)"
            )
        }
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 400, message: ""), operation: .appContentRead),
            String(localized: "Google Play returned an unexpected error (HTTP \(400)).")
        )
    }

    func testBareForbiddenMeansNoAccessToTheApp() {
        XCTAssertEqual(
            message(for: StackError.Http(status: 403, message: "PERMISSION_DENIED")),
            String(localized: "This service account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
        )
    }

    func testNoAccessToTheAppKeepsTheCoresDetailNamingTheAppAndPermission() {
        let detail = "The service account has no access to com.example.app. Grant it \"Reply to reviews\" in Play Console › Users and permissions."

        XCTAssertEqual(
            message(for: StackError.Auth(message: detail)),
            String(localized: "Google Play denied access to this service account.") + "\n" + detail
        )
    }

    func testBadRequestOnReplyMeansTheReplyIsTooLong() {
        let error = StackError.Http(status: 400, message: "Reply text is too long")

        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: error, operation: .replyToReview),
            String(localized: "Google Play rejected this reply. Replies are limited to about \(GooglePlayReviewLimits.replyCharacterLimit) characters — shorten it and try again.")
        )
    }

    func testBadRequestOutsideAReplyStaysGeneric() {
        XCTAssertEqual(
            message(for: StackError.Http(status: 400, message: "bad")),
            String(localized: "Google Play returned an unexpected error (HTTP \(400)).")
        )
    }

    func testReplyLimitMatchesGooglesDocumentedLimit() {
        XCTAssertEqual(GooglePlayReviewLimits.replyCharacterLimit, 350)
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
