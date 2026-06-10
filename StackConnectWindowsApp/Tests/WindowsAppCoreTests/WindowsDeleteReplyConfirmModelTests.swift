import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsDeleteReplyConfirmModel` (T-W25).
///
/// Covers:
/// - TC-038 (P0): Confirm delete success (deleteReply called with responseId,
///   isPending toggles true->false, storage reply fields cleared + saved,
///   didSucceed == true).
/// - TC-038 in-flight (AC-W13-8): isPending == true WHILE delete is in flight
///   (using SuspendableAppleConnection).
/// - TC-044 (P1): Delete API error (isPending true->false, error set, storage
///   reply fields NOT cleared, didSucceed == false).
/// - No-connection guard: nil connection -> error set, no API call, no storage
///   mutation.
/// - No auto-delete on init: model never calls deleteReply automatically.
@MainActor
final class WindowsDeleteReplyConfirmModelTests: XCTestCase {

    private var storage: MockStorage!
    private var connection: MockAppleConnection!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorage()
        connection = MockAppleConnection()
    }

    override func tearDown() async throws {
        storage = nil
        connection = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a SUT with the standard test ids and optional connection.
    private func makeSUT(
        reviewId: String = "review-001",
        responseId: String = "response-001",
        accountId: String = "account-001",
        withConnection: Bool = true
    ) -> WindowsDeleteReplyConfirmModel {
        WindowsDeleteReplyConfirmModel(
            reviewId: reviewId,
            responseId: responseId,
            accountId: accountId,
            storage: storage,
            connection: withConnection ? connection : nil
        )
    }

    /// Seeds a review with an existing reply in storage.
    private func seedReviewWithReply(
        id: String = "review-001",
        rating: Int = 5,
        title: String? = "Great app",
        body: String? = "Love it!",
        responseId: String = "response-001",
        responseBody: String = "Thank you for your feedback!",
        responseState: String = "PUBLISHED",
        responseDate: Date = Date()
    ) async throws {
        let review = CustomerReviewModel(
            id: id,
            rating: rating,
            title: title,
            body: body,
            responseId: responseId,
            responseBody: responseBody,
            responseState: responseState,
            responseDate: responseDate
        )
        try await storage.save(review, id: id)
    }

    // MARK: - TC-038: Confirm Delete Success

    /// TC-038 (P0): deleteReplyConfirmed should call deleteReply with the
    /// correct responseId, toggle isPending true->false, clear the reply fields
    /// in storage, save the updated review, and set didSucceed = true.
    func testConfirmDeleteSuccess_clearsReplyAndSignalsSuccess() async throws {
        // Arrange: seed a review with an existing reply.
        try await seedReviewWithReply(id: "review-001", responseId: "response-001")
        let sut = makeSUT()

        // Pre-conditions
        XCTAssertFalse(sut.isPending, "isPending should start false")
        XCTAssertFalse(sut.didSucceed, "didSucceed should start false")
        XCTAssertNil(sut.error, "error should start nil")

        // Act
        await sut.deleteReplyConfirmed()

        // Assert: connection was called with the correct responseId
        XCTAssertEqual(connection.deleteReplyCallCount, 1)
        XCTAssertEqual(connection.lastDeleteReplyResponseId, "response-001")

        // Assert: state signals success
        XCTAssertFalse(sut.isPending, "isPending should be false after completion")
        XCTAssertTrue(sut.didSucceed, "didSucceed should be true after successful delete")
        XCTAssertNil(sut.error, "error should remain nil on success")

        // Assert: persistence - review reply fields should be cleared
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertNotNil(saved, "Review should still exist in storage")
        XCTAssertNil(saved?.responseId, "responseId should be cleared")
        XCTAssertNil(saved?.responseBody, "responseBody should be cleared")
        XCTAssertNil(saved?.responseState, "responseState should be cleared")
        XCTAssertNil(saved?.responseDate, "responseDate should be cleared")

        // Assert: non-reply fields are preserved
        XCTAssertEqual(saved?.rating, 5)
        XCTAssertEqual(saved?.title, "Great app")
        XCTAssertEqual(saved?.body, "Love it!")
    }

    // MARK: - TC-038 In-Flight: isPending == true While Delete In Flight

    /// AC-W13-8 in-flight: While deleteReplyConfirmed is in flight, isPending
    /// must be true. Uses SuspendableAppleConnection to pause the deleteReply
    /// call and inspect mid-flight state before resuming.
    func testIsPendingTrueWhileDeleteInFlight() async throws {
        // Arrange: seed a review, use suspendable connection
        try await seedReviewWithReply(id: "review-001", responseId: "response-001")
        let suspendable = SuspendableAppleConnection()
        addTeardownBlock { @MainActor [suspendable] in
            suspendable.resumeIfPending()
        }
        let sut = WindowsDeleteReplyConfirmModel(
            reviewId: "review-001",
            responseId: "response-001",
            accountId: "account-001",
            storage: storage,
            connection: suspendable
        )

        // Pre-conditions
        XCTAssertFalse(sut.isPending, "isPending should start false")

        // Act: kick off deleteReplyConfirmed concurrently
        let deleteTask = Task { await sut.deleteReplyConfirmed() }

        // Wait until deleteReply is actually in-flight
        await suspendable.waitForDeleteReplyCall()

        // Assert: mid-flight state
        XCTAssertTrue(sut.isPending, "isPending must be true while delete is in flight")
        XCTAssertFalse(sut.didSucceed, "didSucceed should still be false mid-flight")

        // Resume the connection so deleteReplyConfirmed completes
        suspendable.resumeDeleteReply(with: .success(()))
        await deleteTask.value

        // Post-completion: isPending cleared, didSucceed set
        XCTAssertFalse(sut.isPending, "isPending should be false after completion")
        XCTAssertTrue(sut.didSucceed, "didSucceed should be true after successful delete")
    }

    // MARK: - TC-044: Delete API Error

    /// TC-044 (P1): deleteReplyConfirmed that fails at the API level should set
    /// error, NOT clear the reply in storage, clear isPending, and NOT set
    /// didSucceed (so the screen stays open for retry).
    func testDeleteAPIError_setsErrorAndKeepsReply() async throws {
        // Arrange: seed a review with an existing reply.
        try await seedReviewWithReply(id: "review-001", responseId: "response-001")
        let sut = makeSUT()

        // Configure connection to fail
        connection.deleteReplyResult = .failure(NSError(
            domain: "TestError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Internal Server Error"]
        ))

        let initialSaveCount = storage.saveCallCount

        // Act
        await sut.deleteReplyConfirmed()

        // Assert: connection was called
        XCTAssertEqual(connection.deleteReplyCallCount, 1)

        // Assert: error is set, no success, pending cleared
        XCTAssertEqual(sut.error, "Failed to delete reply.")
        XCTAssertFalse(sut.didSucceed, "didSucceed should remain false on API error")
        XCTAssertFalse(sut.isPending, "isPending should be cleared after error")

        // Assert: storage was NOT mutated (save count unchanged beyond the seed)
        XCTAssertEqual(storage.saveCallCount, initialSaveCount,
                       "Storage should NOT be mutated on API failure")

        // Assert: the original review in storage still has its reply fields
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertNotNil(saved?.responseId, "responseId should be preserved on failure")
        XCTAssertNotNil(saved?.responseBody, "responseBody should be preserved on failure")
        XCTAssertNotNil(saved?.responseState, "responseState should be preserved on failure")
        XCTAssertNotNil(saved?.responseDate, "responseDate should be preserved on failure")
    }

    // MARK: - No Connection Guard

    /// deleteReplyConfirmed with nil connection should set error immediately
    /// without calling the API or mutating storage.
    func testDeleteWithoutConnection_setsError() async throws {
        try await seedReviewWithReply(id: "review-001", responseId: "response-001")
        let sut = makeSUT(withConnection: false)

        let initialSaveCount = storage.saveCallCount

        await sut.deleteReplyConfirmed()

        XCTAssertEqual(sut.error, "No connection available.")
        XCTAssertFalse(sut.didSucceed)
        XCTAssertFalse(sut.isPending)
        XCTAssertEqual(connection.deleteReplyCallCount, 0,
                       "Should not call connection when none is provided")
        XCTAssertEqual(storage.saveCallCount, initialSaveCount,
                       "Storage should NOT be mutated when no connection")
    }

    // MARK: - No Auto-Delete on Init

    /// The model should never automatically call deleteReply on initialization.
    /// This verifies the cancel path at the model level: simply creating the
    /// model does not trigger any API call or state mutation.
    func testNoAutoDeleteOnInit() async throws {
        let sut = makeSUT()

        XCTAssertFalse(sut.isPending, "isPending should be false on init")
        XCTAssertFalse(sut.didSucceed, "didSucceed should be false on init")
        XCTAssertNil(sut.error, "error should be nil on init")
        XCTAssertEqual(connection.deleteReplyCallCount, 0,
                       "deleteReply should not be called on init")
    }

    // MARK: - Persistence Failure After Success (log-and-continue)

    /// When the API delete succeeds but the storage save fails, the model
    /// should still signal success (didSucceed = true) and NOT set error.
    /// The server has already deleted the reply; the next sync will reconcile.
    func testPersistenceFailureAfterSuccess_stillSignalsSuccess() async throws {
        // Arrange: seed a review with a reply, then make storage throw on save
        try await seedReviewWithReply(id: "review-001", responseId: "response-001")
        let sut = makeSUT()

        // Configure storage to throw on save (after the delete succeeds)
        storage.shouldThrowOnSave = true

        // Act
        await sut.deleteReplyConfirmed()

        // Assert: still signals success despite persistence failure
        XCTAssertTrue(sut.didSucceed, "Should signal success even if local save fails")
        XCTAssertNil(sut.error, "error should be nil (persistence failure is logged, not surfaced)")
        XCTAssertFalse(sut.isPending)
    }

    // MARK: - Delete Without Cached Review

    /// When the review is not in cache, the delete should still succeed (the
    /// server delete is what matters). didSucceed should be true, no error.
    func testDeleteWithoutCachedReview_stillSucceeds() async throws {
        // Do NOT seed a review in storage
        let sut = makeSUT()

        await sut.deleteReplyConfirmed()

        XCTAssertEqual(connection.deleteReplyCallCount, 1)
        XCTAssertEqual(connection.lastDeleteReplyResponseId, "response-001")
        XCTAssertTrue(sut.didSucceed, "Should succeed even without cached review")
        XCTAssertNil(sut.error)
        XCTAssertFalse(sut.isPending)
    }
}
