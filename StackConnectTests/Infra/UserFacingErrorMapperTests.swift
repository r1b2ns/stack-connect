import XCTest
import StackCoreRust
import APIProviderFirebase
@testable import StackConnect

/// `UserFacingErrorMapper`: every error becomes a title + detail a user can
/// read — server bodies parsed, plain text trimmed, empty bodies replaced by
/// localized copy — and never JSON, escape sequences or Swift type names.
final class UserFacingErrorMapperTests: XCTestCase {

    // MARK: - Fixtures

    static let ascTitle = "This request is forbidden for security reasons"
    static let ascDetail = "You currently don't have access to this membership resource. Contact your team's Account Holder, or an Admin."

    /// The App Store Connect 403 body exactly as the core passes it (pretty-printed).
    static let asc403Body = """
    {
      "errors" : [ {
        "id" : "6d3e1f1a-0000-4000-8000-000000000000",
        "status" : "403",
        "code" : "FORBIDDEN_ERROR",
        "title" : "\(ascTitle)",
        "resultCode" : 1200,
        "detail" : "\(ascDetail)"
      } ]
    }
    """

    static var asc403: StackError { .Http(status: 403, message: asc403Body) }

    // MARK: - App Store Connect bodies

    func testASCBodyGivesTheServerTitleAndDetail() {
        let mapped = UserFacingErrorMapper.map(Self.asc403)

        XCTAssertEqual(mapped.title, Self.ascTitle)
        XCTAssertEqual(mapped.detail, Self.ascDetail)
        XCTAssertEqual(mapped.message, "\(Self.ascTitle). \(Self.ascDetail)")
        assertReadable(mapped.message)
    }

    func testASCMultipleErrorsKeepTheFirstTitleAndJoinDistinctDetails() {
        let body = #"""
        {"errors":[
          {"status":"409","code":"ENTITY_ERROR.ATTRIBUTE.INVALID","title":"An attribute value is invalid.","detail":"The name is too long."},
          {"status":"409","code":"ENTITY_ERROR.ATTRIBUTE.INVALID","title":"An attribute value is invalid.","detail":"The name is too long."},
          {"status":"409","code":"ENTITY_ERROR.ATTRIBUTE.REQUIRED","title":"A required attribute is missing.","detail":"The SKU is required."}
        ]}
        """#

        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 409, message: body))

        XCTAssertEqual(mapped.title, "An attribute value is invalid.")
        XCTAssertEqual(mapped.detail, "The name is too long.\nThe SKU is required.")
        XCTAssertEqual(mapped.message, "An attribute value is invalid. The name is too long.\nThe SKU is required.")
    }

    func testASCErrorWithoutTitleUsesItsDetail() {
        let body = #"{"errors":[{"status":"404","detail":"The app was not found."}]}"#

        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 404, message: body))

        XCTAssertEqual(mapped, UserFacingError(title: "The app was not found."))
    }

    func testASCErrorsWithoutTextFallBackToTheStatusCopy() {
        let body = #"{"errors":[{"status":"404","code":"NOT_FOUND"}]}"#

        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 404, message: body))

        XCTAssertEqual(mapped.title, String(localized: "The item wasn't found. It may have been deleted."))
        XCTAssertNil(mapped.detail)
    }

    func testJSONAfterAPrefixIsStillParsed() {
        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 403, message: "HTTP 403: " + Self.asc403Body))

        XCTAssertEqual(mapped.title, Self.ascTitle)
        XCTAssertEqual(mapped.detail, Self.ascDetail)
    }

    // MARK: - Google bodies

    func testGoogleAPIBodyGivesItsMessage() {
        let body = #"""
        {"error": {"code": 403, "status": "PERMISSION_DENIED", "message": "The caller does not have permission",
         "errors": [{"message": "The caller does not have permission", "domain": "global", "reason": "forbidden"},
                    {"message": "Project 123 is suspended.", "domain": "global", "reason": "suspended"}]}}
        """#

        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 403, message: body))

        XCTAssertEqual(mapped.title, "The caller does not have permission")
        XCTAssertEqual(mapped.detail, "Project 123 is suspended.")
    }

    func testGoogleAPIBodyWithoutMessageFallsBackToTheStatusCopy() {
        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 401, message: #"{"error": {"code": 401, "status": "UNAUTHENTICATED"}}"#))

        XCTAssertEqual(mapped.title, String(localized: "The server didn't accept the account's credentials. Check the account and try again."))
    }

    func testOAuthBodyGivesItsDescription() {
        let body = #"{"error": "invalid_grant", "error_description": "Invalid JWT Signature."}"#

        let mapped = UserFacingErrorMapper.map(StackError.Auth(message: body))

        XCTAssertEqual(mapped, UserFacingError(title: "Invalid JWT Signature."))
    }

    func testOAuthBodyWithoutDescriptionHumanizesTheCode() {
        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 400, message: #"{"error":"invalid_grant"}"#))

        XCTAssertEqual(mapped.title, "Invalid grant")
    }

    func testFirebaseRequestFailureGivesGooglesMessage() throws {
        let json = #"{"error": {"code": 403, "status": "PERMISSION_DENIED", "message": "Firebase Management API has not been used in project 1."}}"#
        let response = try APIProviderFirebase.jsonDecoder.decode(ErrorResponse.self, from: Data(json.utf8))
        let error = APIProviderFirebase.Error.requestFailure(403, response, URL(string: "https://firebase.googleapis.com/v1beta1/projects"))

        let message = error.userFacingMessage

        XCTAssertEqual(message, "Firebase Management API has not been used in project 1.")
        XCTAssertFalse(message.contains("https://"), "no request URL")
    }

    func testFirebaseFailureWithoutBodyUsesTheStatusCopy() {
        let error = APIProviderFirebase.Error.requestFailure(500, nil, URL(string: "https://firebase.googleapis.com/x"))

        XCTAssertEqual(error.userFacingMessage, String(localized: "The service is temporarily unavailable. Try again in a few minutes."))
    }

    func testFirebaseTokenExchangeFailureReadsTheOAuthBody() {
        let error = FirebaseAuthError.tokenExchangeFailed(statusCode: 400, body: #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#)

        XCTAssertEqual(error.userFacingMessage, "Token has been expired or revoked.")
    }

    // MARK: - Plain text, empty and malformed bodies

    func testPlainTextBodyIsShownTrimmed() {
        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 400, message: "  \n Bad request: the name is empty.\n "))

        XCTAssertEqual(mapped, UserFacingError(title: "Bad request: the name is empty."))
    }

    func testPlainTextWithBracketsIsKeptAsText() {
        let text = "Listing releases quota exceeded. [PERMISSION_DENIED] (HTTP 403 on GET applications/x)"

        XCTAssertEqual(UserFacingErrorMapper.map(StackError.Http(status: 403, message: text)).title, text)
    }

    func testHTMLBodyIsNeverShown() {
        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 502, message: "<html><body><h1>502 Bad Gateway</h1></body></html>"))

        XCTAssertEqual(mapped.title, String(localized: "The service is temporarily unavailable. Try again in a few minutes."))
    }

    func testEmptyBodyFallsBackToLocalizedCopyPerStatus() {
        let expectations: [(UInt16, String)] = [
            (401, String(localized: "The server didn't accept the account's credentials. Check the account and try again.")),
            (403, String(localized: "You don't have permission to do this.")),
            (404, String(localized: "The item wasn't found. It may have been deleted.")),
            (409, String(localized: "This change conflicts with the item's current state. Refresh and try again.")),
            (429, String(localized: "Too many requests. Wait a moment and try again.")),
            (500, String(localized: "The service is temporarily unavailable. Try again in a few minutes.")),
            (503, String(localized: "The service is temporarily unavailable. Try again in a few minutes.")),
            (418, String(localized: "The request failed (HTTP \(418)).")),
        ]
        for (status, expected) in expectations {
            let mapped = UserFacingErrorMapper.map(StackError.Http(status: status, message: "   "))
            XCTAssertEqual(mapped.title, expected, "HTTP \(status)")
            XCTAssertNil(mapped.detail, "HTTP \(status)")
        }
    }

    func testMalformedJSONIsNeverShown() {
        let bodies = [
            #"{"errors" : [ { "title" : "Forbidden", "detail" : "#,
            #"[{"title":"x""#,
            #"Request failed: {"errors": [ {"title": "#,
        ]
        for body in bodies {
            let mapped = UserFacingErrorMapper.map(StackError.Http(status: 403, message: body))
            XCTAssertEqual(mapped.title, String(localized: "You don't have permission to do this."), body)
            assertReadable(mapped.message)
        }
    }

    func testJSONOfAnUnknownShapeIsNeverShown() {
        let mapped = UserFacingErrorMapper.map(StackError.Http(status: 404, message: #"{"foo": {"bar": 1}}"#))

        XCTAssertEqual(mapped.title, String(localized: "The item wasn't found. It may have been deleted."))
    }

    func testVeryLongPlainTextIsCut() {
        let long = String(repeating: "a", count: ServerErrorBody.maxPlainTextLength + 50)

        let title = UserFacingErrorMapper.map(StackError.Http(status: 400, message: long)).title

        XCTAssertEqual(title.count, ServerErrorBody.maxPlainTextLength + 1)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    // MARK: - Non-HTTP StackError cases

    func testSessionExpiredKeepsItsSpecializedCopy() {
        let mapped = UserFacingErrorMapper.map(StackError.SessionExpired(message: "HTTP 401 from iris"))

        XCTAssertEqual(mapped, UserFacingError(title: AppleAPIErrorTranslator.sessionExpiredMessage))
    }

    func testNetworkAndDecodeHideTheCoreText() {
        let network = UserFacingErrorMapper.map(StackError.Network(message: "error sending request for url (https://api.appstoreconnect.apple.com/v1/apps)"))
        let decode = UserFacingErrorMapper.map(StackError.Decode(message: "missing field `data` at line 1 column 2"))

        XCTAssertEqual(network, UserFacingError(title: String(localized: "Couldn't reach the server. Check your internet connection and try again.")))
        XCTAssertEqual(decode, UserFacingError(title: String(localized: "The server returned an unexpected response. Try again later.")))
    }

    func testMessageCasesShowALeadAndTheCoreText() {
        let auth = UserFacingErrorMapper.map(StackError.Auth(message: "Enable the Google Play Developer Reporting API."))
        XCTAssertEqual(auth.title, String(localized: "Access was denied."))
        XCTAssertEqual(auth.detail, "Enable the Google Play Developer Reporting API.")

        let credentials = UserFacingErrorMapper.map(StackError.InvalidCredentials(message: ""))
        XCTAssertEqual(credentials, UserFacingError(title: String(localized: "The account's credentials were rejected. Check them and try again.")))

        let unsupported = UserFacingErrorMapper.map(StackError.Unsupported(message: "Google Play has no API to delete a reply."))
        XCTAssertEqual(unsupported.title, String(localized: "This action isn't supported."))
        XCTAssertEqual(unsupported.detail, "Google Play has no API to delete a reply.")
    }

    func testAJSONMessageInAnAuthErrorReplacesTheLead() {
        let mapped = UserFacingErrorMapper.map(StackError.Auth(message: Self.asc403Body))

        XCTAssertEqual(mapped.title, Self.ascTitle)
        XCTAssertEqual(mapped.detail, Self.ascDetail)
    }

    func testEveryStackErrorCaseIsReadable() {
        let cases: [StackError] = [
            .InvalidCredentials(message: Self.asc403Body),
            .Auth(message: Self.asc403Body),
            .PendingAgreements(message: Self.asc403Body),
            .Http(status: 403, message: Self.asc403Body),
            .Decode(message: Self.asc403Body),
            .Network(message: Self.asc403Body),
            .Unsupported(message: Self.asc403Body),
            .SubmissionNotRemovable(message: Self.asc403Body),
            .ReleaseNotFound(message: Self.asc403Body),
            .SessionExpired(message: Self.asc403Body),
        ]
        for error in cases {
            assertReadable(error.userFacingMessage, "\(error)")
        }
    }

    // MARK: - Other errors

    func testOfflineErrorKeepsItsCopy() {
        XCTAssertEqual(OfflineError.noConnection.userFacingMessage, OfflineError.noConnection.localizedDescription)
    }

    func testOtherErrorsUseTheirLocalizedDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])

        XCTAssertEqual(error.userFacingMessage, "Something went wrong")
        XCTAssertEqual(error.userFacing, UserFacingError(title: "Something went wrong"))
    }

    // MARK: - UserFacingError

    func testMessageJoinsTitleAndDetail() {
        XCTAssertEqual(UserFacingError(title: "Forbidden", detail: "No access.").message, "Forbidden. No access.")
        XCTAssertEqual(UserFacingError(title: "Forbidden.", detail: "No access.").message, "Forbidden. No access.")
        XCTAssertEqual(UserFacingError(title: "Why?", detail: "Because.").message, "Why? Because.")
        XCTAssertEqual(UserFacingError(title: "Only title").message, "Only title")
        XCTAssertNil(UserFacingError(title: "Same", detail: " Same ").detail, "a detail repeating the title is dropped")
    }

    // MARK: - Translators fall back to the mapper

    func testAppleTranslatorFallbackIsReadable() {
        let message = AppleAPIErrorTranslator.friendlyMessage(for: StackError.Decode(message: "missing field `data`"))

        XCTAssertEqual(message, String(localized: "The server returned an unexpected response. Try again later."))
    }

    func testGooglePlayUsersDetailReadsAJSONBody() {
        let message = GooglePlayErrorTranslator.friendlyMessage(for: Self.asc403, operation: .users)

        XCTAssertTrue(message.hasSuffix("\(Self.ascTitle). \(Self.ascDetail)"), message)
        assertReadable(message)
    }

    // MARK: - Helpers

    private func assertReadable(_ message: String, _ context: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(message.isEmpty, context, file: file, line: line)
        XCTAssertFalse(message.contains("{"), "JSON in: \(message) \(context)", file: file, line: line)
        XCTAssertFalse(message.contains("StackError"), "type name in: \(message) \(context)", file: file, line: line)
        XCTAssertFalse(message.contains("\\n"), "escape sequence in: \(message) \(context)", file: file, line: line)
        XCTAssertFalse(message.contains("\\\""), "escape sequence in: \(message) \(context)", file: file, line: line)
    }
}
