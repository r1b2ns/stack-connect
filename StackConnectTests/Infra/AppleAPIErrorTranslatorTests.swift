import XCTest
import StackCoreRust
@testable import StackConnect

final class AppleAPIErrorTranslatorTests: XCTestCase {

    // MARK: - Helpers

    /// Fabricates a `StackCoreRust.StackError.Http` carrying the raw App Store
    /// Connect JSON:API error document the core surfaces verbatim in `message`.
    private func makeError(status: Int, code: String, detail: String? = nil, title: String = "") -> Error {
        let body = "{\"errors\":[{\"status\":\"\(status)\",\"code\":\"\(code)\",\"title\":\"\(title)\",\"detail\":\"\(detail ?? "")\"}]}"
        return StackCoreRust.StackError.Http(status: UInt16(status), message: body)
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

    // MARK: - isConcurrentSubmissionLimit

    /// The real 409 body Apple returns once 5 unfinished review submissions
    /// exist. The specific code is nested under `meta.associatedErrors`; the
    /// top-level code is a generic `STATE_ERROR.ENTITY_STATE_INVALID`.
    private static let concurrentLimitBody = """
    {"errors":[{"id":"11a45c25-5f94-4bbc-a7fa-3e0ffeb5fdf1","status":"409","code":"STATE_ERROR.ENTITY_STATE_INVALID","title":"apps with id '1561937578' is not in valid state.","detail":"This resource cannot be reviewed, please check associated errors to see why.","meta":{"associatedErrors":{"/apps/1561937578":[{"id":"f48da25f-527c-41e4-be10-7c4dd7bec324","status":"409","code":"STATE_ERROR.CONCURRENT_REVIEW_SUBMISSION_LIMIT_EXCEEDED","title":"ReviewSubmission creation concurrency limit is reached","detail":"Unable to create reviewSubmission for appId=1561937578 reviewSubmissionType=DEFAULT platform=IOS as maximum limit=5 of concurrency has reached"}]}}}]}
    """

    private func concurrentLimitError() -> Error {
        StackCoreRust.StackError.Http(status: 409, message: Self.concurrentLimitBody)
    }

    func testConcurrentSubmissionLimitDetectedFromNestedCode() {
        XCTAssertTrue(AppleAPIErrorTranslator.isConcurrentSubmissionLimit(concurrentLimitError()))
    }

    func testUnrelated409IsNotConcurrentSubmissionLimit() {
        let error = makeError(
            status: 409,
            code: "CONFLICT_ERROR",
            detail: "An item with the same value already exists."
        )
        XCTAssertFalse(AppleAPIErrorTranslator.isConcurrentSubmissionLimit(error))
    }

    func testConcurrentSubmissionLimitFalseForNonProviderError() {
        struct Dummy: Error {}
        XCTAssertFalse(AppleAPIErrorTranslator.isConcurrentSubmissionLimit(Dummy()))
    }

    func testConcurrentSubmissionLimitFalseForWrongStatus() {
        // Same code but a 400, not a 409 — must not match.
        let body = "{\"errors\":[{\"status\":\"400\",\"code\":\"STATE_ERROR.CONCURRENT_REVIEW_SUBMISSION_LIMIT_EXCEEDED\"}]}"
        let error = StackCoreRust.StackError.Http(status: 400, message: body)
        XCTAssertFalse(AppleAPIErrorTranslator.isConcurrentSubmissionLimit(error))
    }

    // MARK: - friendlyMessage for concurrency

    func testFriendlyMessageReturnsConcurrencyCopyForNestedCode() {
        let message = AppleAPIErrorTranslator.friendlyMessage(for: concurrentLimitError())
        let expected = String(localized: "You've reached Apple's limit of 5 review submissions in progress for this app. Cancel or submit an existing one before starting a new review.")
        XCTAssertEqual(message, expected)
    }
}
