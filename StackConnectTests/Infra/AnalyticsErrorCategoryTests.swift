import XCTest
import APIProviderFirebase
import StackCoreRust
@testable import StackConnect

/// The `error_category` mapping: real error types in, a fixed raw value out.
final class AnalyticsErrorCategoryTests: XCTestCase {

    // MARK: - Stability

    func testRawValuesAreStableSnakeCase() {
        XCTAssertEqual(AnalyticsErrorCategory.allCases.map(\.rawValue), [
            "validation", "duplicate", "invalid_credentials", "forbidden", "network",
            "server", "wrong_password", "invalid_file", "storage", "scope_denied", "unknown"
        ])
    }

    func testParametersCarryOnlyTheCategory() {
        XCTAssertEqual(AnalyticsErrorCategory.network.parameters, ["error_category": .string("network")])
    }

    // MARK: - Connection errors

    func testCoreErrors() {
        let cases: [(StackError, AnalyticsErrorCategory)] = [
            (.InvalidCredentials(message: "m"), .invalidCredentials),
            (.Auth(message: "m"), .invalidCredentials),
            (.PendingAgreements(message: "m"), .forbidden),
            (.Network(message: "m"), .network),
            (.Http(status: 401, message: "m"), .invalidCredentials),
            (.Http(status: 403, message: "m"), .forbidden),
            (.Http(status: 500, message: "m"), .server),
            (.Http(status: 404, message: "m"), .unknown),
            (.Http(status: 429, message: "m"), .unknown),
            (.Decode(message: "m"), .server),
            (.Unsupported(message: "m"), .unknown)
        ]
        for (error, expected) in cases {
            XCTAssertEqual(AnalyticsErrorCategory(connectionError: error), expected, "\(error)")
        }
    }

    func testLocalAndTransportErrors() {
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: OfflineError.noConnection), .network)
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: GooglePlayServiceAccount.ParseError.malformedJSON), .validation)
        XCTAssertEqual(
            AnalyticsErrorCategory(connectionError: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))),
            .validation
        )
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: NSError(domain: "x", code: 1)), .unknown)
    }

    func testFirebaseErrors() {
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: APIProviderFirebase.Error.requestFailure(401, nil, nil)), .invalidCredentials)
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: APIProviderFirebase.Error.requestFailure(403, nil, nil)), .forbidden)
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: APIProviderFirebase.Error.requestFailure(502, nil, nil)), .server)
        XCTAssertEqual(
            AnalyticsErrorCategory(connectionError: APIProviderFirebase.Error.requestExecutorError(URLError(.timedOut))),
            .network
        )
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: APIProviderFirebase.Error.requestGeneration), .unknown)
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: FirebaseAuthError.invalidPrivateKey), .validation)
        XCTAssertEqual(
            AnalyticsErrorCategory(connectionError: FirebaseAuthError.tokenExchangeFailed(statusCode: 400, body: "invalid_grant")),
            .invalidCredentials
        )
        XCTAssertEqual(
            AnalyticsErrorCategory(connectionError: FirebaseAuthError.tokenExchangeFailed(statusCode: 503, body: nil)),
            .server
        )
    }

    // MARK: - Import

    func testImportReasons() {
        let cases: [(AccountImportError.Reason, AnalyticsErrorCategory)] = [
            (.wrongPassword, .wrongPassword),
            (.invalidFile, .invalidFile),
            (.wrongProvider, .validation),
            (.duplicate, .duplicate),
            (.storage, .storage),
            (.unknown, .unknown)
        ]
        for (reason, expected) in cases {
            XCTAssertEqual(AnalyticsErrorCategory(importReason: reason), expected, "\(reason)")
        }
    }

    @MainActor
    func testDecryptionErrorsMapToImportReasons() {
        XCTAssertEqual(AccountImporter.reason(forDecryptionError: AccountCryptoError.invalidPassword), .wrongPassword)
        XCTAssertEqual(AccountImporter.reason(forDecryptionError: AccountCryptoError.decryptionFailed), .wrongPassword)
        XCTAssertEqual(AccountImporter.reason(forDecryptionError: AccountCryptoError.invalidFileFormat), .invalidFile)
        XCTAssertEqual(AccountImporter.reason(forDecryptionError: AccountCryptoError.unsupportedVersion), .invalidFile)
        XCTAssertEqual(AccountImporter.reason(forDecryptionError: AccountCryptoError.keyDerivationFailed), .unknown)
        XCTAssertEqual(AccountImporter.reason(forDecryptionError: NSError(domain: "x", code: 1)), .unknown)
    }
}
