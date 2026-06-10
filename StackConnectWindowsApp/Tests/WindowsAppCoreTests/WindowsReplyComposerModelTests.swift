import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsReplyComposerModel` (T-W24).
///
/// Covers:
/// - TC-034 (P0): Create submit success (responseId nil -> persisted, didSucceed)
/// - TC-036 (P0): Edit submit success (existingResponseId -> persisted, didSucceed)
/// - TC-043 (P1): Create API error (error set, NOT persisted, pending cleared, NOT didSucceed)
/// - canSubmit: empty input disables (AC-W13-1)
/// - isDirty: tracks whether editor differs from initial body
@MainActor
final class WindowsReplyComposerModelTests: XCTestCase {

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

    /// Creates a SUT for create mode (no existing reply body).
    private func makeSUTForCreate(
        reviewId: String = "review-001",
        accountId: String = "account-001",
        withConnection: Bool = true
    ) -> WindowsReplyComposerModel {
        WindowsReplyComposerModel(
            reviewId: reviewId,
            accountId: accountId,
            existingReplyBody: nil,
            existingResponseId: nil,
            storage: storage,
            connection: withConnection ? connection : nil
        )
    }

    /// Creates a SUT for edit mode (existing reply body + responseId).
    private func makeSUTForEdit(
        reviewId: String = "review-001",
        accountId: String = "account-001",
        existingBody: String = "Old reply text",
        existingResponseId: String = "response-001",
        withConnection: Bool = true
    ) -> WindowsReplyComposerModel {
        WindowsReplyComposerModel(
            reviewId: reviewId,
            accountId: accountId,
            existingReplyBody: existingBody,
            existingResponseId: existingResponseId,
            storage: storage,
            connection: withConnection ? connection : nil
        )
    }

    /// Seeds a review in storage so the composer can fetch it for persistence.
    private func seedReview(
        id: String = "review-001",
        rating: Int = 5,
        title: String? = "Great app",
        body: String? = "Love it!",
        responseId: String? = nil,
        responseBody: String? = nil
    ) async throws {
        let review = CustomerReviewModel(
            id: id,
            rating: rating,
            title: title,
            body: body,
            responseId: responseId,
            responseBody: responseBody
        )
        try await storage.save(review, id: id)
    }

    // MARK: - TC-034: Create Submit Success

    /// TC-034 (P0): submitReply with responseId=nil should call upsert, set
    /// isPending true->false, persist the review with the reply, and set
    /// didSucceed = true so the view pops.
    func testCreateSubmitSuccess_persistsAndSignalsSuccess() async throws {
        // Arrange: seed a review in cache so persistence can update it.
        try await seedReview(id: "review-001")
        let sut = makeSUTForCreate()

        // Pre-conditions
        XCTAssertFalse(sut.isPending, "isPending should start false")
        XCTAssertFalse(sut.didSucceed, "didSucceed should start false")
        XCTAssertNil(sut.error, "error should start nil")

        // Act
        await sut.submitReply(responseBody: "Thank you for the feedback!")

        // Assert: connection was called with nil existingResponseId (create)
        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertEqual(connection.lastUpsertReplyReviewId, "review-001")
        XCTAssertNil(connection.lastUpsertReplyExistingResponseId, "Create mode should pass nil responseId")
        XCTAssertEqual(connection.lastUpsertReplyBody, "Thank you for the feedback!")

        // Assert: state signals success
        XCTAssertFalse(sut.isPending, "isPending should be false after completion")
        XCTAssertTrue(sut.didSucceed, "didSucceed should be true after successful submit")
        XCTAssertNil(sut.error, "error should remain nil on success")

        // Assert: persistence - review should have the reply fields set
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertNotNil(saved, "Review should be persisted")
        XCTAssertEqual(saved?.responseBody, "Thank you for the feedback!")
        XCTAssertEqual(saved?.responseState, "PENDING_PUBLISH")
        XCTAssertNotNil(saved?.responseDate, "responseDate should be set")
        XCTAssertEqual(saved?.responseId, "local-review-001", "Create should assign local placeholder responseId")
    }

    // MARK: - TC-036: Edit Submit Success

    /// TC-036 (P0): submitReply with existingResponseId should call upsert with
    /// the responseId, set isPending true->false, persist the updated reply,
    /// and set didSucceed = true so the view pops.
    func testEditSubmitSuccess_persistsAndSignalsSuccess() async throws {
        // Arrange: seed a review with an existing response.
        try await seedReview(
            id: "review-001",
            responseId: "response-001",
            responseBody: "Old reply text"
        )
        let sut = makeSUTForEdit()

        // Pre-conditions
        XCTAssertFalse(sut.isPending)
        XCTAssertFalse(sut.didSucceed)
        XCTAssertEqual(sut.text, "Old reply text", "Edit mode should pre-populate text")

        // Act
        await sut.submitReply(responseBody: "Updated reply text")

        // Assert: connection was called with the existing responseId (edit)
        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertEqual(connection.lastUpsertReplyReviewId, "review-001")
        XCTAssertEqual(connection.lastUpsertReplyExistingResponseId, "response-001",
                       "Edit mode should pass the existing responseId")
        XCTAssertEqual(connection.lastUpsertReplyBody, "Updated reply text")

        // Assert: state signals success
        XCTAssertFalse(sut.isPending)
        XCTAssertTrue(sut.didSucceed)
        XCTAssertNil(sut.error)

        // Assert: persistence - review should have the updated reply body + date
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.responseBody, "Updated reply text")
        XCTAssertEqual(saved?.responseState, "PENDING_PUBLISH")
        XCTAssertNotNil(saved?.responseDate)
        // Edit keeps original responseId (not overwritten with local-*)
        XCTAssertEqual(saved?.responseId, "response-001",
                       "Edit should preserve the existing responseId")
    }

    // MARK: - TC-043: Create API Error

    /// TC-043 (P1): submitReply that fails at the API level should set error,
    /// NOT persist any changes, clear isPending, and NOT set didSucceed (so
    /// the view stays open for retry).
    func testCreateAPIError_setsErrorAndDoesNotPersist() async throws {
        // Arrange: seed a review without a response.
        try await seedReview(id: "review-001")
        let sut = makeSUTForCreate()

        // Configure connection to fail
        connection.upsertReplyResult = .failure(NSError(
            domain: "TestError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Internal Server Error"]
        ))

        let initialSaveCount = storage.saveCallCount

        // Act
        await sut.submitReply(responseBody: "This should fail")

        // Assert: connection was called
        XCTAssertEqual(connection.upsertReplyCallCount, 1)

        // Assert: error is set, no success, pending cleared
        XCTAssertEqual(sut.error, "Failed to save reply.")
        XCTAssertFalse(sut.didSucceed, "didSucceed should remain false on API error")
        XCTAssertFalse(sut.isPending, "isPending should be cleared after error")

        // Assert: storage was NOT mutated (save count unchanged beyond the seed)
        // The seed called save once; the failed submit should NOT call save again.
        XCTAssertEqual(storage.saveCallCount, initialSaveCount,
                       "Storage should NOT be mutated on API failure")

        // Assert: the original review in storage is unchanged
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertNil(saved?.responseBody, "Original review should have no response body")
        XCTAssertNil(saved?.responseId, "Original review should have no response id")
    }

    // MARK: - canSubmit: Empty Disables (AC-W13-1)

    /// AC-W13-1: canSubmit should be false when text is empty, and true when
    /// text is non-empty and not pending.
    func testCanSubmit_emptyTextDisables() {
        let sut = makeSUTForCreate()

        // Initially empty -> canSubmit false
        XCTAssertEqual(sut.text, "")
        XCTAssertFalse(sut.canSubmit, "Empty text should disable submit")

        // Whitespace-only -> canSubmit false
        sut.text = "   "
        XCTAssertFalse(sut.canSubmit, "Whitespace-only text should disable submit")

        // Non-empty -> canSubmit true
        sut.text = "Hello"
        XCTAssertTrue(sut.canSubmit, "Non-empty text should enable submit")
    }

    /// After a successful submit completes, isPending is cleared and canSubmit
    /// reflects the text state (non-empty -> true). This is a post-completion
    /// check, not an in-flight check.
    func testCanSubmit_trueAfterSuccessfulSubmitCompletes() async throws {
        try await seedReview(id: "review-001")
        let sut = makeSUTForCreate()
        sut.text = "Some reply"

        // Before submit: canSubmit true
        XCTAssertTrue(sut.canSubmit)

        // After successful submit: isPending is false, didSucceed is true
        // so canSubmit is based on text (still true since text is non-empty)
        await sut.submitReply(responseBody: sut.text)
        XCTAssertFalse(sut.isPending)
        XCTAssertTrue(sut.canSubmit, "canSubmit should be true after pending clears")
    }

    /// AC-W13-2: While submitReply is in flight, isPending must be true and
    /// canSubmit must be false. Uses SuspendableAppleConnection to pause the
    /// upsertReply call and inspect mid-flight state before resuming.
    func testIsPendingTrueAndCanSubmitFalseWhileSubmitInFlight() async throws {
        // Arrange: seed a review, use suspendable connection
        try await seedReview(id: "review-001")
        let suspendable = SuspendableAppleConnection()
        addTeardownBlock { @MainActor [suspendable] in
            suspendable.resumeIfPending()
        }
        let sut = WindowsReplyComposerModel(
            reviewId: "review-001",
            accountId: "account-001",
            existingReplyBody: nil,
            existingResponseId: nil,
            storage: storage,
            connection: suspendable
        )
        sut.text = "In-flight test reply"

        // Pre-conditions
        XCTAssertFalse(sut.isPending, "isPending should start false")
        XCTAssertTrue(sut.canSubmit, "canSubmit should start true with non-empty text")

        // Act: kick off submitReply concurrently
        let submitTask = Task { await sut.submitReply(responseBody: sut.text) }

        // Wait until upsertReply is actually in-flight
        await suspendable.waitForUpsertReplyCall()

        // Assert: mid-flight state
        XCTAssertTrue(sut.isPending, "isPending must be true while submit is in flight")
        XCTAssertFalse(sut.canSubmit, "canSubmit must be false while isPending is true")
        XCTAssertFalse(sut.didSucceed, "didSucceed should still be false mid-flight")

        // Resume the connection so submitReply completes
        suspendable.resumeUpsertReply(with: .success(()))
        await submitTask.value

        // Post-completion: isPending cleared, didSucceed set
        XCTAssertFalse(sut.isPending, "isPending should be false after completion")
        XCTAssertTrue(sut.didSucceed, "didSucceed should be true after successful submit")
    }

    // MARK: - isDirty: Tracks Changes

    /// isDirty should reflect whether the editor text differs from the initial
    /// body provided at init.
    func testIsDirty_tracksChangesFromInitialBody() {
        // Create mode: initial body is ""
        let createSUT = makeSUTForCreate()
        XCTAssertFalse(createSUT.isDirty, "Create mode starts clean (empty == empty)")

        createSUT.text = "New text"
        XCTAssertTrue(createSUT.isDirty, "Typing makes it dirty")

        createSUT.text = ""
        XCTAssertFalse(createSUT.isDirty, "Clearing back to empty is clean again")

        // Edit mode: initial body is "Old reply text"
        let editSUT = makeSUTForEdit()
        XCTAssertFalse(editSUT.isDirty, "Edit mode starts clean (text == existing body)")

        editSUT.text = "Modified text"
        XCTAssertTrue(editSUT.isDirty, "Changing text from existing body is dirty")

        editSUT.text = "Old reply text"
        XCTAssertFalse(editSUT.isDirty, "Restoring to exact existing body is clean")
    }

    // MARK: - No Connection

    /// Submit without a connection should set error immediately without
    /// calling the API.
    func testSubmitWithoutConnection_setsError() async throws {
        let sut = makeSUTForCreate(withConnection: false)
        sut.text = "Reply text"

        await sut.submitReply(responseBody: sut.text)

        XCTAssertEqual(sut.error, "No connection available.")
        XCTAssertFalse(sut.didSucceed)
        XCTAssertFalse(sut.isPending)
        XCTAssertEqual(connection.upsertReplyCallCount, 0,
                       "Should not call connection when none is provided")
    }

    // MARK: - Edit Pre-Population (AC-W13-5)

    /// AC-W13-5: Edit mode should pre-populate the text with the existing body.
    func testEditPrePopulatesText() {
        let sut = makeSUTForEdit(existingBody: "Existing developer response")
        XCTAssertEqual(sut.text, "Existing developer response",
                       "Edit mode should pre-populate text with existing body")
    }

    // MARK: - Resolve Existing Response ID from Cache

    /// When no explicit existingResponseId is given, the model should resolve
    /// it from the cached review's responseId.
    func testResolveExistingResponseId_fromCache() async throws {
        // Seed a review with a responseId in cache.
        try await seedReview(
            id: "review-001",
            responseId: "response-from-cache",
            responseBody: "Cached reply"
        )

        // Create model WITHOUT explicit existingResponseId but with existing body.
        let sut = WindowsReplyComposerModel(
            reviewId: "review-001",
            accountId: "account-001",
            existingReplyBody: "Cached reply",
            existingResponseId: nil,
            storage: storage,
            connection: connection
        )

        let resolved = await sut.resolveExistingResponseId()
        XCTAssertEqual(resolved, "response-from-cache",
                       "Should resolve responseId from cached review")
    }

    // MARK: - Edit Submit via Cache Resolution

    /// When existingResponseId is NOT passed at init but the cached review has
    /// a responseId, submitReply should use the cache-resolved responseId.
    func testEditSubmitViaCache_usesResolvedResponseId() async throws {
        // Seed a review with a responseId in cache.
        try await seedReview(
            id: "review-001",
            responseId: "response-from-cache",
            responseBody: "Old cached reply"
        )

        // Create model with existing body but NO explicit responseId.
        let sut = WindowsReplyComposerModel(
            reviewId: "review-001",
            accountId: "account-001",
            existingReplyBody: "Old cached reply",
            existingResponseId: nil,
            storage: storage,
            connection: connection
        )

        await sut.submitReply(responseBody: "Updated via cache")

        // Assert: connection received the cache-resolved responseId
        XCTAssertEqual(connection.lastUpsertReplyExistingResponseId, "response-from-cache",
                       "Should use responseId resolved from cache")
        XCTAssertTrue(sut.didSucceed)
    }

    // MARK: - Explicit existingResponseId via init (AC-W13-3, Blocking #2)

    /// Edit mode where the explicit existingResponseId is provided via init.
    /// The upsert must be called with that exact responseId, closing the
    /// duplicate-reply path (AC-W13-3).
    func testEditWithExplicitResponseId_usesItForUpsert() async throws {
        try await seedReview(id: "review-001")
        let sut = WindowsReplyComposerModel(
            reviewId: "review-001",
            accountId: "account-001",
            existingReplyBody: "Existing body",
            existingResponseId: "explicit-response-id",
            storage: storage,
            connection: connection
        )

        await sut.submitReply(responseBody: "Updated reply")

        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertEqual(connection.lastUpsertReplyExistingResponseId, "explicit-response-id",
                       "Upsert should use the explicit responseId from init, not resolve from cache")
        XCTAssertTrue(sut.didSucceed)
    }

    /// Edit mode where the explicit init existingResponseId is nil but the
    /// storage cache HAS a responseId. The fallback should resolve and the
    /// upsert should use the cached responseId.
    func testEditWithNilExplicitId_fallsBackToCacheResponseId() async throws {
        // Seed a review with a responseId in cache.
        try await seedReview(
            id: "review-001",
            responseId: "cached-response-id",
            responseBody: "Cached body"
        )

        // Create model WITHOUT explicit responseId.
        let sut = WindowsReplyComposerModel(
            reviewId: "review-001",
            accountId: "account-001",
            existingReplyBody: "Cached body",
            existingResponseId: nil,
            storage: storage,
            connection: connection
        )

        await sut.submitReply(responseBody: "Edited via fallback")

        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertEqual(connection.lastUpsertReplyExistingResponseId, "cached-response-id",
                       "Upsert should fall back to cached responseId when init value is nil")
        XCTAssertTrue(sut.didSucceed)
    }

    /// Create mode (no explicit id, no cached id). The upsert must be called
    /// with nil existingResponseId.
    func testCreateMode_upsertCalledWithNilResponseId() async throws {
        // Seed a review WITHOUT a responseId.
        try await seedReview(id: "review-001")

        let sut = WindowsReplyComposerModel(
            reviewId: "review-001",
            accountId: "account-001",
            existingReplyBody: nil,
            existingResponseId: nil,
            storage: storage,
            connection: connection
        )

        await sut.submitReply(responseBody: "Brand new reply")

        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertNil(connection.lastUpsertReplyExistingResponseId,
                     "Create mode should pass nil existingResponseId to upsert")
        XCTAssertTrue(sut.didSucceed)
    }

    /// When an explicit responseId is provided via init, resolveExistingResponseId
    /// should return it directly without hitting storage.
    func testResolveExistingResponseId_prefersExplicitOverCache() async throws {
        // Seed a review with a DIFFERENT responseId in cache.
        try await seedReview(
            id: "review-001",
            responseId: "cached-response-id",
            responseBody: "Cached body"
        )

        let sut = WindowsReplyComposerModel(
            reviewId: "review-001",
            accountId: "account-001",
            existingReplyBody: "Cached body",
            existingResponseId: "explicit-response-id",
            storage: storage,
            connection: connection
        )

        let resolved = await sut.resolveExistingResponseId()
        XCTAssertEqual(resolved, "explicit-response-id",
                       "Explicit responseId should take precedence over cache")
    }
}
