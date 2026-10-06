import XCTest
@testable import StackConnect

/// Covers the host-side service-account JSON → core fields conversion (plan D2).
final class GooglePlayServiceAccountTests: XCTestCase {

    private typealias ParseError = GooglePlayServiceAccount.ParseError
    private typealias Fixtures = GooglePlayTestFixtures

    private func assertThrows(
        _ expected: ParseError,
        parsing json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try GooglePlayServiceAccount(json: json), file: file, line: line) { error in
            XCTAssertEqual(error as? ParseError, expected, file: file, line: line)
        }
    }

    // MARK: - Valid key files

    func testParsesAllFieldsOfAValidKeyFile() throws {
        let account = try GooglePlayServiceAccount(json: Fixtures.serviceAccountJSON())

        XCTAssertEqual(account.clientEmail, Fixtures.clientEmail)
        XCTAssertEqual(account.privateKeyId, Fixtures.privateKeyId)
        XCTAssertEqual(account.privateKey, "-----BEGIN PRIVATE KEY-----\nMIIEfake\n-----END PRIVATE KEY-----\n")
        XCTAssertEqual(account.projectId, Fixtures.projectId)
    }

    func testDecodesTheJSONEscapedPEMIntoRealNewlines() throws {
        // Exactly what Google writes: the PEM's newlines are JSON `\n` escapes.
        let json = #"""
        {
          "type": "service_account",
          "project_id": "my-project",
          "private_key_id": "abc123",
          "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEline1\nline2==\n-----END PRIVATE KEY-----\n",
          "client_email": "sa@my-project.iam.gserviceaccount.com",
          "client_id": "1234567890",
          "token_uri": "https://oauth2.googleapis.com/token"
        }
        """#

        let account = try GooglePlayServiceAccount(json: json)

        XCTAssertEqual(account.privateKey, "-----BEGIN PRIVATE KEY-----\nMIIEline1\nline2==\n-----END PRIVATE KEY-----\n")
        XCTAssertFalse(account.privateKey.contains("\\n"), "JSON escapes must be decoded, not kept literally")
    }

    func testPassesTheKeyThroughByteForByte() throws {
        // A double-escaped PEM (literal backslash-n) is handed to the core as-is:
        // the core accepts JSON-escaped PEMs, so the parser must not rewrite it.
        let doubleEscaped = #"-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n"#
        let json = Fixtures.serviceAccountJSON(privateKey: doubleEscaped)

        let account = try GooglePlayServiceAccount(json: json)

        XCTAssertEqual(account.privateKey, doubleEscaped)
    }

    func testTrimsSurroundingWhitespaceOfTheFileAndIdentifiers() throws {
        let json = "\n  " + Fixtures.serviceAccountJSON(
            clientEmail: "  \(Fixtures.clientEmail) ",
            privateKeyId: " \(Fixtures.privateKeyId)\n"
        ) + "  \n"

        let account = try GooglePlayServiceAccount(json: json)

        XCTAssertEqual(account.clientEmail, Fixtures.clientEmail)
        XCTAssertEqual(account.privateKeyId, Fixtures.privateKeyId)
    }

    func testTypeIsOptional() throws {
        let account = try GooglePlayServiceAccount(json: Fixtures.serviceAccountJSON(type: nil))
        XCTAssertEqual(account.clientEmail, Fixtures.clientEmail)
    }

    func testProjectIdIsOptional() throws {
        let missing = try GooglePlayServiceAccount(json: Fixtures.serviceAccountJSON(projectId: nil))
        let blank = try GooglePlayServiceAccount(json: Fixtures.serviceAccountJSON(projectId: "  "))

        XCTAssertNil(missing.projectId)
        XCTAssertNil(blank.projectId)
    }

    func testParsesStoredCredentials() throws {
        let credentials = GooglePlayCredentials(serviceAccountJSON: Fixtures.serviceAccountJSON())

        let account = try GooglePlayServiceAccount(credentials: credentials)

        XCTAssertEqual(account.clientEmail, Fixtures.clientEmail)
    }

    // MARK: - Empty / malformed

    func testEmptyOrWhitespaceOnlyThrowsEmpty() {
        assertThrows(.empty, parsing: "")
        assertThrows(.empty, parsing: " \n\t ")
    }

    func testMalformedJSONThrowsMalformed() {
        assertThrows(.malformedJSON, parsing: "not json at all")
        assertThrows(.malformedJSON, parsing: #"{"type": "service_account", "client_email": "#)
        assertThrows(.malformedJSON, parsing: #"["service_account"]"#)
        assertThrows(.malformedJSON, parsing: #"{"client_email": 42}"#)
    }

    // MARK: - Wrong type / missing fields

    func testNonServiceAccountTypeThrowsUnsupportedType() {
        assertThrows(
            .unsupportedType("authorized_user"),
            parsing: Fixtures.serviceAccountJSON(type: "authorized_user")
        )
    }

    func testMissingOrBlankClientEmailThrowsMissingField() {
        assertThrows(.missingField(.clientEmail), parsing: Fixtures.serviceAccountJSON(clientEmail: nil))
        assertThrows(.missingField(.clientEmail), parsing: Fixtures.serviceAccountJSON(clientEmail: "   "))
    }

    func testMissingOrBlankPrivateKeyIdThrowsMissingField() {
        assertThrows(.missingField(.privateKeyId), parsing: Fixtures.serviceAccountJSON(privateKeyId: nil))
        assertThrows(.missingField(.privateKeyId), parsing: Fixtures.serviceAccountJSON(privateKeyId: ""))
    }

    func testMissingOrBlankPrivateKeyThrowsMissingField() {
        assertThrows(.missingField(.privateKey), parsing: Fixtures.serviceAccountJSON(privateKey: nil))
        assertThrows(.missingField(.privateKey), parsing: Fixtures.serviceAccountJSON(privateKey: "\n  \n"))
    }

    func testClientEmailWithoutAtSignThrowsInvalidClientEmail() {
        assertThrows(.invalidClientEmail, parsing: Fixtures.serviceAccountJSON(clientEmail: "not-an-email"))
    }

    // MARK: - Messages

    func testEveryErrorHasUserFacingCopy() {
        let errors: [ParseError] = [
            .empty,
            .malformedJSON,
            .unsupportedType("authorized_user"),
            .missingField(.clientEmail),
            .invalidClientEmail
        ]
        for error in errors {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty, "\(error) must have a message")
            XCTAssertFalse(message.contains("ParseError"), "\(error) must not leak the type name")
        }
    }

    func testMissingFieldMessageNamesTheJSONField() {
        XCTAssertTrue(ParseError.missingField(.privateKeyId).localizedDescription.contains("private_key_id"))
        XCTAssertEqual(ParseError.empty.localizedDescription, String(localized: "Service Account JSON is required."))
    }
}
