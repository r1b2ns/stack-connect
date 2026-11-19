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

    // MARK: - Google sign-in accounts

    func testAuthLeadNamesTheSignedInGoogleAccount() {
        let detail = "The caller does not have permission"

        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: detail), authMethod: .googleSignIn),
            String(localized: "Google Play denied access to the signed-in Google account.") + "\n" + detail
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: " "), authMethod: .googleSignIn),
            String(localized: "Google Play denied access to the signed-in Google account.")
        )
        // A service account keeps its wording.
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: " "), authMethod: .keyFile),
            String(localized: "Google Play denied access to this service account.")
        )
    }

    func testUsersAuthLeadNamesTheSignedInGoogleAccount() {
        let signIn = String(localized: "To manage users, the signed-in Google account needs the “Admin (all permissions)” permission in Play Console › Users and permissions.")
        let serviceAccount = String(localized: "To manage users, this service account needs the “Admin (all permissions)” permission in Play Console › Users and permissions.")

        for operation in [GooglePlayErrorTranslator.Operation.users, .inviteUser, .userChange] {
            XCTAssertEqual(
                GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: ""), operation: operation, authMethod: .googleSignIn),
                signIn
            )
            XCTAssertEqual(
                GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: ""), operation: operation),
                serviceAccount
            )
        }
    }

    func testForbiddenNamesTheSignedInGoogleAccount() {
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), authMethod: .googleSignIn),
            String(localized: "The signed-in Google account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), operation: .releaseChange, authMethod: .googleSignIn),
            String(localized: "The signed-in Google account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: "")),
            String(localized: "This service account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), operation: .users, authMethod: .googleSignIn),
            String(localized: "Google Play refused access to this developer account. Check the Developer ID, and that the signed-in Google account has the “Admin (all permissions)” permission.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), operation: .users),
            String(localized: "Google Play refused access to this developer account. Check the Developer ID, and that the service account has the “Admin (all permissions)” permission.")
        )
    }

    func testSignInCopyNamesTheGoogleAccountEmailWhenKnown() {
        let email = "dev@example.com"
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: "detail"), authMethod: .googleSignIn, accountEmail: email),
            String(localized: "Google Play denied access to the Google account \(email).") + "\ndetail"
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: ""), operation: .users, authMethod: .googleSignIn, accountEmail: email),
            String(localized: "To manage users, the Google account \(email) needs the “Admin (all permissions)” permission in Play Console › Users and permissions.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), authMethod: .googleSignIn, accountEmail: email),
            String(localized: "The Google account \(email) can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), operation: .releaseChange, authMethod: .googleSignIn, accountEmail: email),
            String(localized: "The Google account \(email) can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
        )
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), operation: .inviteUser, authMethod: .googleSignIn, accountEmail: email),
            String(localized: "Google Play refused access to this developer account. Check the Developer ID, and that the Google account \(email) has the “Admin (all permissions)” permission.")
        )
    }

    func testAnEmptyOrMissingEmailKeepsTheGenericSignInCopy() {
        for email in [nil, "", "  "] as [String?] {
            XCTAssertEqual(
                GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), authMethod: .googleSignIn, accountEmail: email),
                String(localized: "The signed-in Google account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
            )
        }
    }

    func testAServiceAccountNeverNamesAnEmail() {
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: ""), authMethod: .keyFile, accountEmail: "dev@example.com"),
            String(localized: "This service account can't access this app. In Play Console › Users and permissions, give it access to the app and try again.")
        )
    }

    func testUsersFailureNamesTheEmail() {
        let failure = GooglePlayErrorTranslator.usersFailure(
            StackError.Auth(message: ""), call: GooglePlayUsersCall(.list, developerId: "1234"), logTag: "Tests",
            authMethod: .googleSignIn, accountEmail: "dev@example.com"
        )

        XCTAssertEqual(failure.message, String(localized: "To manage users, the Google account \("dev@example.com") needs the “Admin (all permissions)” permission in Play Console › Users and permissions."))
    }

    func testUsersFailureUsesTheAccountsAuthMethod() {
        let call = GooglePlayUsersCall(.list, developerId: "1234")
        let failure = GooglePlayErrorTranslator.usersFailure(
            StackError.Auth(message: ""), call: call, logTag: "Tests", authMethod: .googleSignIn
        )

        XCTAssertEqual(failure.message, String(localized: "To manage users, the signed-in Google account needs the “Admin (all permissions)” permission in Play Console › Users and permissions."))
    }

    func testNetworkErrorIsTreatedAsOffline() {
        let error = StackError.Network(message: "error sending request: connection refused")

        XCTAssertEqual(message(for: error), String(localized: "Couldn't reach Google Play. Check your internet connection and try again."))
        XCTAssertTrue(GooglePlayErrorTranslator.isOffline(error))
    }

    func testRateLimit() {
        XCTAssertEqual(
            message(for: StackError.Http(status: 429, message: "RESOURCE_EXHAUSTED")),
            String(localized: "Google Play's API quota for this account was reached. Wait a few minutes and try again.") + "\nRESOURCE_EXHAUSTED"
        )
    }

    /// The core reports every Google quota or rate limit as Http 429 (even a
    /// 403 "Listing releases quota exceeded."): every operation shows the
    /// quota copy with Google's own text, never the permission or developer
    /// ID copy.
    func testQuotaIsTheSameFriendlyCopyForEveryOperation() {
        let core = "Listing releases quota exceeded. [PERMISSION_DENIED]; this is a Google Play API quota/rate limit, "
            + "not a permission problem — wait and retry later (Retry-After: 60 s) (HTTP 403 on GET developers/5374/users)"
        let expected = String(localized: "Google Play's API quota for this account was reached. Wait a few minutes and try again.") + "\nListing releases quota exceeded. [PERMISSION_DENIED]"
        let operations: [GooglePlayErrorTranslator.Operation] = [
            .general, .appContentRead, .replyToReview, .releaseChange, .users, .inviteUser, .userChange
        ]
        for operation in operations {
            let text = GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 429, message: core), operation: operation)
            XCTAssertEqual(text, expected, "\(operation)")
            XCTAssertFalse(text.contains("Admin"), "Not the permission copy (\(operation))")
            XCTAssertFalse(text.contains("Developer ID"), "Not the developer ID copy (\(operation))")
        }
        XCTAssertEqual(
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 429, message: "  "), operation: .users),
            String(localized: "Google Play's API quota for this account was reached. Wait a few minutes and try again."),
            "Without Google's text, the lead alone"
        )
    }

    func testAQuotaNeverAsksForTheDeveloperIdAgain() {
        let quota = StackError.Http(
            status: 429,
            message: "Quota exceeded [RESOURCE_EXHAUSTED]; this is a Google Play API quota/rate limit, not a permission problem "
                + "— wait and retry later (HTTP 403 on GET developers/5374/users)"
        )
        XCTAssertFalse(GooglePlayErrorTranslator.asksForDeveloperId(quota))
        XCTAssertFalse(GooglePlayErrorTranslator.isWrongDeveloperId(quota))
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
                String(localized: "Google Play's API quota for this account was reached. Wait a few minutes and try again."),
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

    func testReleaseNotFoundAsksToRefresh() {
        XCTAssertEqual(
            message(for: StackError.ReleaseNotFound(message: "gone")),
            String(localized: "This release changed on Google Play since it was loaded. Refresh and try again.")
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
            .Unsupported(message: "g"), .SubmissionNotRemovable(message: "h"), .ReleaseNotFound(message: "i")
        ]
        for error in errors {
            XCTAssertFalse(message(for: error).contains("StackError"), "\(error) leaked its debug description")
        }
    }
}
