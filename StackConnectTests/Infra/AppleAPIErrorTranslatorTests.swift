import XCTest
import AppStoreConnect_Swift_SDK
@testable import StackConnect

final class AppleAPIErrorTranslatorTests: XCTestCase {

    // MARK: - Helpers

    /// Fabricates an `APIProvider.Error.requestFailure` carrying a single
    /// `ResponseError` with the given fields. `ResponseError` and `ErrorResponse`
    /// both expose public memberwise initializers, so the SDK error is directly
    /// constructible without a JSON fixture.
    private func makeError(status: Int, code: String, detail: String? = nil, title: String = "") -> Error {
        let responseError = ResponseError(
            status: String(status),
            code: code,
            title: title,
            detail: detail
        )
        let response = ErrorResponse(errors: [responseError])
        return APIProvider.Error.requestFailure(status, response, nil)
    }

    // MARK: - isPendingAgreement

    func testAgreementCodeReturnsTrue() {
        let error = makeError(
            status: 403,
            code: "FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED",
            detail: "You must accept the latest agreements."
        )
        XCTAssertTrue(AppleAPIErrorTranslator.isPendingAgreement(error))
    }

    func testUnknownCodeButDetailMentionsAgreementReturnsTrue() {
        let error = makeError(
            status: 403,
            code: "SOME_UNKNOWN_CODE",
            detail: "Your Paid Apps Agreement is pending and must be accepted."
        )
        XCTAssertTrue(AppleAPIErrorTranslator.isPendingAgreement(error))
    }

    func testNonAgreement403ReturnsFalse() {
        let error = makeError(
            status: 403,
            code: "FORBIDDEN_ERROR",
            detail: "This operation is not permitted."
        )
        XCTAssertFalse(AppleAPIErrorTranslator.isPendingAgreement(error))
    }

    func test401ReturnsFalse() {
        let error = makeError(
            status: 401,
            code: "FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED",
            detail: "agreement"
        )
        XCTAssertFalse(AppleAPIErrorTranslator.isPendingAgreement(error))
    }

    func test500ReturnsFalse() {
        let error = makeError(
            status: 500,
            code: "INTERNAL_ERROR",
            detail: "Something agreement broke"
        )
        XCTAssertFalse(AppleAPIErrorTranslator.isPendingAgreement(error))
    }

    func testNonProviderErrorReturnsFalse() {
        struct Dummy: Error {}
        XCTAssertFalse(AppleAPIErrorTranslator.isPendingAgreement(Dummy()))
    }

    // MARK: - isForbidden

    func testForbidden403WithForbiddenCodeReturnsTrue() {
        let error = makeError(
            status: 403,
            code: "FORBIDDEN_ERROR",
            detail: "The API key in use does not allow this request."
        )
        XCTAssertTrue(AppleAPIErrorTranslator.isForbidden(error))
    }

    func testForbidden403WithOtherCodeReturnsFalse() {
        let error = makeError(
            status: 403,
            code: "CONFLICT_ERROR",
            detail: "An item with the same value already exists."
        )
        XCTAssertFalse(AppleAPIErrorTranslator.isForbidden(error))
    }

    func testForbidden401WithForbiddenCodeReturnsFalse() {
        let error = makeError(
            status: 401,
            code: "FORBIDDEN_ERROR",
            detail: "The API key in use does not allow this request."
        )
        XCTAssertFalse(AppleAPIErrorTranslator.isForbidden(error))
    }

    func testForbiddenNonProviderErrorReturnsFalse() {
        let error = NSError(domain: "test", code: 403)
        XCTAssertFalse(AppleAPIErrorTranslator.isForbidden(error))
    }
}
