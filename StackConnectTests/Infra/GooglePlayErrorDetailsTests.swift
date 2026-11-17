import XCTest
import StackCoreRust
@testable import StackConnect

/// Technical details of Google Play errors (operation, kind, status, source,
/// raw message, developer ID, resource, service account) and the friendly
/// message of the users operations. Labels are localized, so assertions check
/// the dynamic values or compare against `String(localized:)`.
final class GooglePlayErrorDetailsTests: XCTestCase {

    private let serviceAccount = GooglePlayTestFixtures.clientEmail

    /// The core's own message for a developer ID that isn't digits-only
    /// (`ensure_developer_id`, raised before any request).
    private let localDeveloperIdMessage = "local validation failed: developer ID \"abc\" is not numeric (3 chars: letters); "
        + "it is the number after /developers/ in a Play Console URL; request not sent to Google"

    /// The core's message for Google's 404 on `developers/{id}/users`.
    private let googleNotFoundMessage = "Google Play found no developer account with ID 1234 (HTTP 404): check the "
        + "developer ID. Google said: Developer not found. [NOT_FOUND] (HTTP 404 on GET developers/1234/users)"

    /// The core's `Auth` for Google's 403 when the service account isn't Admin.
    private var missingAdminMessage: String {
        "The service account \(serviceAccount) cannot access the developer account 1234. Invite it in Play Console > "
            + "Users and permissions with at least \"Admin (all permissions)\"; new access can take a while to propagate. "
            + "Google said: The caller does not have the CAN_MANAGE_PERMISSIONS_GLOBAL permission. [PERMISSION_DENIED] "
            + "(HTTP 403 on GET developers/1234/users)"
    }

    private func listCall(_ developerId: String) -> GooglePlayUsersCall {
        GooglePlayUsersCall(.list, developerId: developerId, serviceAccountEmail: serviceAccount)
    }

    // MARK: - Friendly message (users operations)

    func testALocallyRejectedDeveloperIdExplainsTheIdAndKeepsTheCoresMessage() {
        let message = GooglePlayErrorTranslator.friendlyMessage(
            for: StackError.Http(status: 404, message: localDeveloperIdMessage), operation: .users
        )

        XCTAssertEqual(message, GooglePlayDeveloperId.invalidMessage + "\n" + localDeveloperIdMessage)
        XCTAssertFalse(
            message.contains(String(localized: "Google Play found no developer account with this ID. Check the Developer ID in Play Console › Settings › Developer account.")),
            "Nothing was sent: Google can't have said it found no account"
        )
        XCTAssertTrue(GooglePlayErrorTranslator.isWrongDeveloperId(StackError.Http(status: 404, message: localDeveloperIdMessage)),
                      "Still offers to change the ID")
    }

    func testGooglesNotFoundKeepsTheLeadAndAppendsGooglesMessage() {
        let message = GooglePlayErrorTranslator.friendlyMessage(
            for: StackError.Http(status: 404, message: googleNotFoundMessage), operation: .users
        )

        XCTAssertEqual(
            message,
            String(localized: "Google Play found no developer account with this ID. Check the Developer ID in Play Console › Settings › Developer account.")
                + "\n" + googleNotFoundMessage
        )
    }

    func testUsersStatusesAppendTheMessageForEveryUsersOperation() {
        let forbidden = GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 403, message: "Forbidden [PERMISSION_DENIED]"), operation: .users)
        XCTAssertTrue(forbidden.hasSuffix("\nForbidden [PERMISSION_DENIED]"))

        let change = GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 500, message: "Internal error [INTERNAL]"), operation: .userChange)
        XCTAssertEqual(change, String(localized: "Google Play is temporarily unavailable. Try again in a few minutes.") + "\nInternal error [INTERNAL]")

        let blank = GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 500, message: "  \n"), operation: .userChange)
        XCTAssertEqual(blank, String(localized: "Google Play is temporarily unavailable. Try again in a few minutes."), "No empty detail line")
    }

    func testOtherOperationsStillDropTheRawMessage() {
        let message = GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 500, message: "Internal error"), operation: .general)
        XCTAssertEqual(message, String(localized: "Google Play is temporarily unavailable. Try again in a few minutes."))
    }

    func testALocallyRejectedInviteAddressIsNotBlamedOnGoogle() {
        let local = "local validation failed: \"a***@x\" is not a valid e-mail address (5 chars: letters, whitespace, '@'); "
            + "request not sent to Google"
        let message = GooglePlayErrorTranslator.friendlyMessage(for: StackError.Http(status: 400, message: local), operation: .inviteUser)

        XCTAssertEqual(message, String(localized: "Google Play couldn't send this invitation.") + "\n" + local)
    }

    func testLocalRejectionRecognizesTheCoresWordingsOnly() {
        XCTAssertTrue(GooglePlayErrorTranslator.isLocalRejection(localDeveloperIdMessage))
        XCTAssertTrue(GooglePlayErrorTranslator.isLocalRejection(
            "local validation failed: userFraction 1.5 is not between 0 and 1, exclusive; request not sent to Google"
        ))
        XCTAssertTrue(GooglePlayErrorTranslator.isLocalRejection(
            "\"a b@x\" is not a valid e-mail address (checked locally; nothing was sent to Google)."
        ), "The core's previous wording is still recognized")
        XCTAssertFalse(GooglePlayErrorTranslator.isLocalRejection(googleNotFoundMessage))
        XCTAssertFalse(GooglePlayErrorTranslator.isLocalRejection(missingAdminMessage))
    }

    func testMissingAdminKeepsTheAdminLeadAndTheCoresMessage() {
        let message = GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: missingAdminMessage), operation: .users)

        XCTAssertEqual(
            message,
            String(localized: "To manage users, this service account needs the “Admin (all permissions)” permission in Play Console › Users and permissions.")
                + "\n" + missingAdminMessage
        )
    }

    // MARK: - Technical details

    func testDetailsOfALocallyRejectedDeveloperId() {
        let lines = GooglePlayErrorTranslator.technicalDetails(
            for: StackError.Http(status: 404, message: localDeveloperIdMessage), operation: .users, call: listCall("abc")
        )

        XCTAssertEqual(lines, [
            String(localized: "Operation: \("developers.users.list")"),
            String(localized: "Error kind: \("StackError.Http")"),
            String(localized: "HTTP status: \(404)"),
            String(localized: "Source: \(String(localized: "StackConnect, before any request (nothing was sent to Google)"))"),
            String(localized: "Message: \(localDeveloperIdMessage)"),
            String(localized: "Developer ID (as stored): \("\"abc\"")"),
            String(localized: "Developer ID length: \(3)"),
            String(localized: "Developer ID format: not digits only (Google needs the number from the Play Console URL)"),
            String(localized: "Developer ID unexpected characters: \("U+0061, U+0062, U+0063")"),
            String(localized: "Resource: \("developers/abc/users")"),
            String(localized: "Service account: \(serviceAccount)")
        ])
    }

    func testDetailsOfGooglesNotFound() {
        let lines = GooglePlayErrorTranslator.technicalDetails(
            for: StackError.Http(status: 404, message: googleNotFoundMessage), operation: .users, call: listCall("1234")
        )

        XCTAssertTrue(lines.contains(String(localized: "Source: \(String(localized: "Google Play API (Google's answer)"))")))
        XCTAssertTrue(lines.contains(String(localized: "Message: \(googleNotFoundMessage)")), "Google's message verbatim")
        XCTAssertTrue(lines.contains(String(localized: "Developer ID format: digits only")))
        XCTAssertFalse(lines.contains { $0.contains("U+") }, "No unexpected characters line for a numeric ID")
        XCTAssertTrue(lines.contains(String(localized: "Resource: \("developers/1234/users")")))
    }

    func testDetailsOfMissingAdminHaveNoStatusButTheAuthMessage() {
        let lines = GooglePlayErrorTranslator.technicalDetails(
            for: StackError.Auth(message: missingAdminMessage), operation: .users, call: listCall("1234")
        )

        XCTAssertTrue(lines.contains(String(localized: "Error kind: \("StackError.Auth")")))
        XCTAssertNil(GooglePlayErrorDetails(error: StackError.Auth(message: missingAdminMessage), operation: .users).httpStatus,
                     "The core reports the 403 as Auth: no status to print")
        XCTAssertTrue(lines.contains(String(localized: "Message: \(missingAdminMessage)")))
        XCTAssertTrue(lines.contains(String(localized: "Service account: \(serviceAccount)")))
    }

    func testDetailsOfANonUsersErrorNameTheOperationOnly() {
        let lines = GooglePlayErrorTranslator.technicalDetails(for: StackError.Network(message: "timed out"), operation: .replyToReview)

        XCTAssertEqual(lines, [
            String(localized: "Operation: \("reviews.reply")"),
            String(localized: "Error kind: \("StackError.Network")"),
            String(localized: "Source: \(String(localized: "Network (the request may not have reached Google)"))"),
            String(localized: "Message: \("timed out")")
        ])
    }

    func testDetailsOfTheOfflineGuardAndAKeyFileError() {
        let offline = GooglePlayErrorDetails(error: OfflineError.noConnection, operation: .users)
        XCTAssertEqual(offline.kind, "OfflineError.noConnection")
        XCTAssertEqual(offline.source, .connection)
        XCTAssertNil(offline.message)

        let keyFile = GooglePlayErrorDetails(error: GooglePlayServiceAccount.ParseError.missingField(.privateKey), operation: .users)
        XCTAssertEqual(keyFile.source, .keyFile)
        XCTAssertEqual(keyFile.operation, "developers.users.list")
    }

    func testUnexpectedCharactersOfAPastedIdAreListedAsCodePoints() {
        let lines = GooglePlayDeveloperId.diagnosticLines(for: "12 3\u{200B}", label: .entered)

        XCTAssertEqual(lines.first, String(localized: "Developer ID (as entered): \("\"12 3\u{200B}\"")"))
        XCTAssertTrue(lines.contains(String(localized: "Developer ID length: \(5)")))
        XCTAssertTrue(lines.contains(String(localized: "Developer ID unexpected characters: \("U+0020, U+200B")")))
    }

    // MARK: - Users calls

    func testResourcePathsAndOperations() {
        XCTAssertEqual(GooglePlayUsersCall(.list, developerId: "1").resourcePath, "developers/1/users")
        XCTAssertEqual(GooglePlayUsersCall(.invite, developerId: "1", email: "a@x.example").resourcePath, "developers/1/users")
        XCTAssertEqual(GooglePlayUsersCall(.update, developerId: "1", email: "a@x.example").resourcePath, "developers/1/users/a@x.example")
        XCTAssertEqual(GooglePlayUsersCall(.delete, developerId: "1", email: "a@x.example").resourcePath, "developers/1/users/a@x.example")
        XCTAssertEqual(
            GooglePlayUsersCall(.setGrant, developerId: "1", email: "a@x.example", packageName: "com.x.one").resourcePath,
            "developers/1/users/a@x.example/grants/com.x.one"
        )
        XCTAssertEqual(GooglePlayUsersCall(.list, developerId: "1").operation, .users)
        XCTAssertEqual(GooglePlayUsersCall(.invite, developerId: "1").operation, .inviteUser)
        XCTAssertEqual(GooglePlayUsersCall(.deleteGrant, developerId: "1").operation, .userChange)
    }

    func testUsersFailureCarriesTheMessageAndTheDetails() {
        let error = StackError.Http(status: 404, message: googleNotFoundMessage)
        let failure = GooglePlayErrorTranslator.usersFailure(error, call: listCall("1234"), logTag: "Tests")

        XCTAssertEqual(failure.message, GooglePlayErrorTranslator.friendlyMessage(for: error, operation: .users))
        XCTAssertEqual(failure.technicalDetails, GooglePlayErrorTranslator.technicalDetails(for: error, operation: .users, call: listCall("1234")))
    }

    // MARK: - Secrets

    func testSecretsInAMessageAreRedacted() {
        let keyId = GooglePlayTestFixtures.privateKeyId
        let leaky = """
            token ya29.a0AfB_byC-secret_token and Authorization: Bearer abc.def-ghi \
            {"private_key_id": "\(keyId)", "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEfake\\n-----END PRIVATE KEY-----\\n"} \
            -----BEGIN PRIVATE KEY-----
            MIIEfake
            -----END PRIVATE KEY-----
            access_token=sekret&x=1 eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl key \(keyId)
            """
        let details = GooglePlayErrorDetails(error: StackError.Auth(message: leaky), operation: .users, call: listCall("1234"))
        let text = details.lines.joined(separator: "\n")

        for secret in ["ya29.", "abc.def-ghi", keyId, "MIIEfake", "PRIVATE KEY", "sekret", "eyJhbGciOiJSUzI1NiJ9"] {
            XCTAssertFalse(text.contains(secret), "Details leak \(secret)")
        }
        XCTAssertTrue(text.contains(serviceAccount), "The service account e-mail is a public identifier and stays")
    }

    func testRedactionKeepsOrdinaryMessages() {
        XCTAssertEqual(GooglePlayErrorDetails.redactingSecrets(googleNotFoundMessage), googleNotFoundMessage)
        XCTAssertEqual(GooglePlayErrorDetails.redactingSecrets(missingAdminMessage), missingAdminMessage)
    }
}
