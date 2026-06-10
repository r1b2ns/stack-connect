import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsReviewDetailModel` (T-W26).
///
/// Covers:
/// - TC-032 (P0): `loadReviewIfNeeded` with cached review populates uiState fields
/// - TC-033 (P0): Review with no reply -> replyMode == .create
/// - TC-035 (P0): Review with existing reply -> replyMode == .edit(responseId:)
///   (arbiter is `responseId != nil`, not `hasResponse`)
/// - TC-037 (P0): Delete-reply data: model exposes correct responseId for the
///   view to push the delete-confirm route
/// - sendReply success (create + edit), failure, in-flight pending
/// - deleteReply success, failure, in-flight pending
/// - TC-040 (clipboard success): "Copied!" message + formatted text verification
/// - TC-041 (clipboard host fallback): graceful fallback message
/// - Clipboard auto-dismiss with injectable delay
/// - TC-042 (network error cache fallback): cached review + syncError banner
/// - Guard paths: missing connection, missing review
@MainActor
final class WindowsReviewDetailModelTests: XCTestCase {

    private var storage: MockStorage!
    private var connection: MockAppleConnection!
    private var clipboard: MockClipboardProvider!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorage()
        connection = MockAppleConnection()
        clipboard = MockClipboardProvider()
    }

    override func tearDown() async throws {
        storage = nil
        connection = nil
        clipboard = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a SUT with the standard test dependencies.
    private func makeSUT(
        withConnection: Bool = true,
        clipboardSucceeds: Bool = true,
        clipboardAutoDismissDelay: UInt64 = 0
    ) -> WindowsReviewDetailModel {
        clipboard.shouldSucceed = clipboardSucceeds
        return WindowsReviewDetailModel(
            storage: storage,
            connection: withConnection ? connection : nil,
            clipboard: clipboard,
            clipboardAutoDismissDelay: clipboardAutoDismissDelay
        )
    }

    /// Seeds a review in storage.
    private func seedReview(
        id: String = "review-001",
        rating: Int = 4,
        title: String? = "Great app",
        body: String? = "Really enjoying this!",
        reviewerNickname: String? = "JohnDoe",
        createdDate: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        territory: String? = "US",
        responseId: String? = nil,
        responseBody: String? = nil,
        responseState: String? = nil,
        responseDate: Date? = nil
    ) async throws {
        let review = CustomerReviewModel(
            id: id,
            rating: rating,
            title: title,
            body: body,
            reviewerNickname: reviewerNickname,
            createdDate: createdDate,
            territory: territory,
            responseId: responseId,
            responseBody: responseBody,
            responseState: responseState,
            responseDate: responseDate
        )
        try await storage.save(review, id: id)
    }

    /// Configures the mock connection to return the given review in fetchReviews.
    private func configureConnectionWithReview(_ review: CustomerReviewModel) {
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [review], hasNextPage: false, cursor: nil)
        )
    }

    // MARK: - TC-032: loadReviewIfNeeded with Cached Review

    /// TC-032 (P0): Loading a cached review should populate uiState.review with
    /// all expected fields (rating, title, body, reviewerNickname, territory,
    /// createdDate, response fields). Offline-first: loads from storage cache.
    func testLoadReviewIfNeeded_cachedReview_populatesUiState() async throws {
        // Arrange: seed a review with all fields populated.
        let responseDate = Date(timeIntervalSince1970: 1_700_100_000)
        try await seedReview(
            id: "review-001",
            rating: 5,
            title: "Fantastic",
            body: "Best app ever",
            reviewerNickname: "Alice",
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            territory: "GB",
            responseId: "resp-001",
            responseBody: "Thank you!",
            responseState: "PUBLISHED",
            responseDate: responseDate
        )
        // No live sync: connection returns empty page (review not found on live)
        let sut = makeSUT()

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Assert: review is populated from cache
        let review = sut.uiState.review
        XCTAssertNotNil(review, "Review should be loaded from cache")
        XCTAssertEqual(review?.id, "review-001")
        XCTAssertEqual(review?.rating, 5)
        XCTAssertEqual(review?.title, "Fantastic")
        XCTAssertEqual(review?.body, "Best app ever")
        XCTAssertEqual(review?.reviewerNickname, "Alice")
        XCTAssertEqual(review?.territory, "GB")
        XCTAssertEqual(review?.createdDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(review?.responseId, "resp-001")
        XCTAssertEqual(review?.responseBody, "Thank you!")
        XCTAssertEqual(review?.responseState, "PUBLISHED")
        XCTAssertEqual(review?.responseDate, responseDate)
        XCTAssertFalse(sut.uiState.isLoading, "isLoading should be false after load completes")
    }

    // MARK: - TC-033: Review with No Reply -> .create

    /// TC-033 (P0): A review without a reply (responseId == nil) should result
    /// in replyMode == .create ("Write a Reply" state).
    func testLoadReview_noReply_replyModeIsCreate() async throws {
        // Arrange: seed a review without any response fields
        try await seedReview(id: "review-001", responseId: nil, responseBody: nil)
        let sut = makeSUT()

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Assert
        XCTAssertEqual(sut.uiState.replyMode, .create, "Review without reply should be in create mode")
        XCTAssertEqual(sut.uiState.replyMode.buttonLabel, "Write a Reply")
        XCTAssertNil(sut.uiState.existingReplyBody, "No existing reply body in create mode")
        XCTAssertNil(sut.uiState.existingReplyDate, "No existing reply date in create mode")
    }

    // MARK: - TC-035: Review with Existing Reply -> .edit(responseId:)

    /// TC-035 (P0): A review with an existing reply (responseId != nil) should
    /// result in replyMode == .edit(responseId:) with the correct responseId.
    /// The arbiter is `responseId != nil`, NOT `hasResponse` (per T-W22 fix).
    func testLoadReview_withReply_replyModeIsEditWithResponseId() async throws {
        // Arrange: seed a review with a response (responseId is the arbiter)
        try await seedReview(
            id: "review-001",
            responseId: "resp-999",
            responseBody: "Developer response here",
            responseState: "PUBLISHED",
            responseDate: Date(timeIntervalSince1970: 1_700_050_000)
        )
        let sut = makeSUT()

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Assert
        XCTAssertEqual(sut.uiState.replyMode, .edit(responseId: "resp-999"),
                       "Review with responseId should be in edit mode with that responseId")
        XCTAssertEqual(sut.uiState.replyMode.buttonLabel, "Edit Reply")
        XCTAssertEqual(sut.uiState.existingReplyBody, "Developer response here")
        XCTAssertEqual(sut.uiState.existingReplyDate, Date(timeIntervalSince1970: 1_700_050_000))
    }

    /// TC-035 edge case: A review with a responseId but EMPTY responseBody
    /// (PENDING_PUBLISH transition) should STILL be in edit mode (responseId
    /// is the arbiter, not hasResponse).
    func testLoadReview_responseIdWithEmptyBody_stillEditMode() async throws {
        // Arrange: responseId present, but body is nil (PENDING_PUBLISH)
        try await seedReview(
            id: "review-001",
            responseId: "resp-pending",
            responseBody: nil,
            responseState: "PENDING_PUBLISH"
        )
        let sut = makeSUT()

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Assert: should be edit, not create (guards against duplicate-reply bug)
        XCTAssertEqual(sut.uiState.replyMode, .edit(responseId: "resp-pending"),
                       "responseId != nil means edit mode, even if body is nil/empty")
    }

    // MARK: - TC-037: Delete-Reply Data (Model-Side)

    /// TC-037 (P0): When the review has an existing reply, the model exposes the
    /// correct responseId in .edit(responseId:) so the view can push the
    /// delete-confirm route with (reviewId, responseId, accountId).
    func testDeleteReplyData_exposesCorrectResponseId() async throws {
        // Arrange
        try await seedReview(
            id: "review-002",
            responseId: "resp-to-delete",
            responseBody: "Old reply"
        )
        let sut = makeSUT()

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-002", appId: "app-001", accountId: "acc-001")

        // Assert: extract the responseId from replyMode
        guard case .edit(let responseId) = sut.uiState.replyMode else {
            XCTFail("Expected .edit mode, got \(sut.uiState.replyMode)")
            return
        }
        XCTAssertEqual(responseId, "resp-to-delete",
                       "Model should expose the responseId the view needs for the delete-confirm route")
        XCTAssertEqual(sut.uiState.review?.id, "review-002",
                       "Review id should be available for the delete route")
    }

    // MARK: - sendReply Success (Create Mode)

    /// sendReply in create mode (no existing responseId): calls upsertReply with
    /// existingResponseId == nil, persists updated review, updates uiState.
    func testSendReply_createSuccess_persistsAndUpdatesState() async throws {
        // Arrange: seed a review without a response
        try await seedReview(id: "review-001")
        let sut = makeSUT()
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")
        XCTAssertEqual(sut.uiState.replyMode, .create)

        let initialSaveCount = storage.saveCallCount

        // Act
        await sut.sendReply(responseBody: "New reply text")

        // Assert: connection called with nil existingResponseId (create)
        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertEqual(connection.lastUpsertReplyReviewId, "review-001")
        XCTAssertNil(connection.lastUpsertReplyExistingResponseId,
                     "Create mode should pass nil existingResponseId")
        XCTAssertEqual(connection.lastUpsertReplyBody, "New reply text")

        // Assert: uiState updated
        XCTAssertFalse(sut.uiState.isReplyPending)
        XCTAssertNil(sut.uiState.replyError)
        XCTAssertEqual(sut.uiState.review?.responseBody, "New reply text")
        XCTAssertEqual(sut.uiState.review?.responseState, "PENDING_PUBLISH")
        XCTAssertNotNil(sut.uiState.review?.responseDate)
        XCTAssertEqual(sut.uiState.review?.responseId, "local-review-001",
                       "Create should assign local placeholder responseId")

        // Assert: now in edit mode with the local placeholder id
        XCTAssertEqual(sut.uiState.replyMode, .edit(responseId: "local-review-001"))

        // Assert: persisted
        XCTAssertGreaterThan(storage.saveCallCount, initialSaveCount,
                             "Updated review should be persisted")
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertEqual(saved?.responseBody, "New reply text")
    }

    // MARK: - sendReply Success (Edit Mode)

    /// sendReply in edit mode (existing responseId): calls upsertReply with the
    /// existing responseId, persists the updated review.
    func testSendReply_editSuccess_persistsAndUpdatesState() async throws {
        // Arrange: seed a review with an existing response
        try await seedReview(
            id: "review-001",
            responseId: "resp-existing",
            responseBody: "Old reply",
            responseState: "PUBLISHED",
            responseDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let sut = makeSUT()
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")
        XCTAssertEqual(sut.uiState.replyMode, .edit(responseId: "resp-existing"))

        // Act
        await sut.sendReply(responseBody: "Updated reply text")

        // Assert: connection called with the existing responseId (edit)
        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertEqual(connection.lastUpsertReplyExistingResponseId, "resp-existing",
                       "Edit mode should pass the existing responseId")
        XCTAssertEqual(connection.lastUpsertReplyBody, "Updated reply text")

        // Assert: uiState updated with new body, preserves responseId
        XCTAssertEqual(sut.uiState.review?.responseBody, "Updated reply text")
        XCTAssertEqual(sut.uiState.review?.responseId, "resp-existing",
                       "Edit mode should preserve the existing responseId")
        XCTAssertEqual(sut.uiState.review?.responseState, "PENDING_PUBLISH")
        XCTAssertFalse(sut.uiState.isReplyPending)
        XCTAssertNil(sut.uiState.replyError)

        // Assert: still in edit mode with same responseId
        XCTAssertEqual(sut.uiState.replyMode, .edit(responseId: "resp-existing"))

        // Assert: persisted
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertEqual(saved?.responseBody, "Updated reply text")
    }

    // MARK: - sendReply Failure

    /// sendReply API failure: error surfaced in replyError, storage NOT corrupted,
    /// review unchanged, isReplyPending cleared.
    func testSendReply_failure_setsErrorAndPreservesState() async throws {
        // Arrange
        try await seedReview(id: "review-001")
        let sut = makeSUT()
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        connection.upsertReplyResult = .failure(NSError(
            domain: "TestError", code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Server error"]
        ))
        let saveCountBeforeSend = storage.saveCallCount

        // Act
        await sut.sendReply(responseBody: "This should fail")

        // Assert: error surfaced
        XCTAssertEqual(sut.uiState.replyError, "Failed to save reply.")
        XCTAssertFalse(sut.uiState.isReplyPending)

        // Assert: storage NOT mutated (save count unchanged beyond the load phase)
        XCTAssertEqual(storage.saveCallCount, saveCountBeforeSend,
                       "Storage should NOT be mutated on API failure")

        // Assert: review in storage is unchanged (no response added)
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertNil(saved?.responseBody, "Original review should be unchanged on failure")
        XCTAssertNil(saved?.responseId, "Original review should be unchanged on failure")
    }

    // MARK: - sendReply In-Flight Pending (SuspendableAppleConnection)

    /// While sendReply is in flight, isReplyPending must be true and replyError
    /// must be nil. Uses SuspendableAppleConnection.
    func testSendReply_inFlight_isReplyPendingTrue() async throws {
        // Arrange
        try await seedReview(id: "review-001")
        let suspendable = SuspendableAppleConnection()
        addTeardownBlock { @MainActor [suspendable] in
            suspendable.resumeIfPending()
        }
        let sut = WindowsReviewDetailModel(
            storage: storage,
            connection: suspendable,
            clipboard: clipboard,
            clipboardAutoDismissDelay: 0
        )
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Pre-conditions
        XCTAssertFalse(sut.uiState.isReplyPending)

        // Act: kick off sendReply concurrently
        let sendTask = Task { await sut.sendReply(responseBody: "In-flight reply") }
        await suspendable.waitForUpsertReplyCall()

        // Assert: mid-flight state
        XCTAssertTrue(sut.uiState.isReplyPending, "isReplyPending must be true while in flight")
        XCTAssertNil(sut.uiState.replyError, "replyError should be nil while in flight")

        // Resume
        suspendable.resumeUpsertReply(with: .success(()))
        await sendTask.value

        // Post-completion
        XCTAssertFalse(sut.uiState.isReplyPending)
    }

    // MARK: - deleteReply Success

    /// deleteReply success: calls connection.deleteReply with the correct
    /// responseId, clears reply fields, restores create mode, persists.
    func testDeleteReply_success_clearsReplyAndRestoresCreateMode() async throws {
        // Arrange: seed a review with an existing response
        try await seedReview(
            id: "review-001",
            responseId: "resp-to-delete",
            responseBody: "Reply to delete",
            responseState: "PUBLISHED",
            responseDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let sut = makeSUT()
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")
        XCTAssertEqual(sut.uiState.replyMode, .edit(responseId: "resp-to-delete"))

        // Act
        await sut.deleteReply()

        // Assert: connection called
        XCTAssertEqual(connection.deleteReplyCallCount, 1)
        XCTAssertEqual(connection.lastDeleteReplyResponseId, "resp-to-delete")

        // Assert: state cleared
        XCTAssertEqual(sut.uiState.replyMode, .create, "Should restore create mode after delete")
        XCTAssertNil(sut.uiState.existingReplyBody)
        XCTAssertNil(sut.uiState.existingReplyDate)
        XCTAssertFalse(sut.uiState.isReplyPending)
        XCTAssertNil(sut.uiState.replyError)

        // Assert: review fields cleared
        XCTAssertNil(sut.uiState.review?.responseId)
        XCTAssertNil(sut.uiState.review?.responseBody)
        XCTAssertNil(sut.uiState.review?.responseState)
        XCTAssertNil(sut.uiState.review?.responseDate)

        // Assert: persisted
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertNil(saved?.responseId)
        XCTAssertNil(saved?.responseBody)
    }

    // MARK: - deleteReply Failure

    /// deleteReply API failure: replyError set, reply kept, storage unchanged.
    func testDeleteReply_failure_setsErrorAndKeepsReply() async throws {
        // Arrange
        try await seedReview(
            id: "review-001",
            responseId: "resp-keep",
            responseBody: "Keep this reply",
            responseState: "PUBLISHED"
        )
        let sut = makeSUT()
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        connection.deleteReplyResult = .failure(NSError(
            domain: "TestError", code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Server error"]
        ))
        let saveCountBeforeDelete = storage.saveCallCount

        // Act
        await sut.deleteReply()

        // Assert
        XCTAssertEqual(sut.uiState.replyError, "Failed to delete reply.")
        XCTAssertFalse(sut.uiState.isReplyPending)
        XCTAssertEqual(sut.uiState.replyMode, .edit(responseId: "resp-keep"),
                       "Reply mode should be preserved on failure")

        // Assert: storage NOT mutated
        XCTAssertEqual(storage.saveCallCount, saveCountBeforeDelete)
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertEqual(saved?.responseId, "resp-keep")
        XCTAssertEqual(saved?.responseBody, "Keep this reply")
    }

    // MARK: - deleteReply In-Flight Pending

    /// While deleteReply is in flight, isReplyPending must be true.
    func testDeleteReply_inFlight_isReplyPendingTrue() async throws {
        // Arrange
        try await seedReview(
            id: "review-001",
            responseId: "resp-inflight",
            responseBody: "Reply"
        )
        let suspendable = SuspendableAppleConnection()
        addTeardownBlock { @MainActor [suspendable] in
            suspendable.resumeIfPending()
        }
        let sut = WindowsReviewDetailModel(
            storage: storage,
            connection: suspendable,
            clipboard: clipboard,
            clipboardAutoDismissDelay: 0
        )
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Act: kick off deleteReply concurrently
        let deleteTask = Task { await sut.deleteReply() }
        await suspendable.waitForDeleteReplyCall()

        // Assert: mid-flight
        XCTAssertTrue(sut.uiState.isReplyPending, "isReplyPending must be true while delete is in flight")

        // Resume
        suspendable.resumeDeleteReply(with: .success(()))
        await deleteTask.value

        XCTAssertFalse(sut.uiState.isReplyPending)
    }

    // MARK: - TC-040: Clipboard Copy Success (Windows Happy Path)

    /// TC-040: copyReviewToClipboard with injected clipboard returning true
    /// sets clipboardMessage == "Copied!" and the clipboard receives the full
    /// formatted review text.
    func testCopyReviewToClipboard_success_copiedMessage() async throws {
        // Arrange: seed a fully populated review
        let createdDate = Date(timeIntervalSince1970: 1_700_000_000)
        try await seedReview(
            id: "review-001",
            rating: 4,
            title: "Great app",
            body: "Really enjoying this!",
            reviewerNickname: "JohnDoe",
            createdDate: createdDate,
            territory: "US"
        )
        let sut = makeSUT(clipboardSucceeds: true)
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Act
        sut.copyReviewToClipboard()

        // Assert: message
        XCTAssertEqual(sut.uiState.clipboardMessage, "Copied!")

        // Assert: clipboard received formatted text
        XCTAssertEqual(clipboard.setTextCallCount, 1)
        let copiedText = clipboard.lastSetText!

        // Verify the formatted text includes the expected components
        // Stars: 4 filled + 1 empty
        XCTAssertTrue(copiedText.hasPrefix("\u{2605}\u{2605}\u{2605}\u{2605}\u{2606}"),
                      "Should start with 4 filled + 1 empty star")
        XCTAssertTrue(copiedText.contains("Great app"), "Should contain title")
        XCTAssertTrue(copiedText.contains("Really enjoying this!"), "Should contain body")
        XCTAssertTrue(copiedText.contains("by JohnDoe"), "Should contain reviewer nickname")
        // Territory display name for "US"
        let territoryDisplay = Locale.current.localizedString(forRegionCode: "US") ?? "US"
        XCTAssertTrue(copiedText.contains(territoryDisplay), "Should contain territory display name")
        // Date formatted via WindowsDateFormatting.absoluteDate
        let formattedDate = WindowsDateFormatting.absoluteDate(createdDate)
        XCTAssertTrue(copiedText.contains(formattedDate), "Should contain formatted date")
    }

    // MARK: - TC-041: Clipboard Host Fallback (macOS/Non-Windows)

    /// TC-041: copyReviewToClipboard with injected clipboard returning false
    /// sets the graceful fallback message.
    func testCopyReviewToClipboard_hostFallback_fallbackMessage() async throws {
        // Arrange
        try await seedReview(id: "review-001")
        let sut = makeSUT(clipboardSucceeds: false)
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Act
        sut.copyReviewToClipboard()

        // Assert
        XCTAssertEqual(sut.uiState.clipboardMessage, "Clipboard not available on this host")
        XCTAssertEqual(clipboard.setTextCallCount, 1, "Should still attempt the clipboard call")
    }

    // MARK: - Clipboard Auto-Dismiss

    /// With an injectable small clipboardAutoDismissDelay, the clipboard message
    /// should clear after the delay.
    func testCopyReviewToClipboard_autoDismiss_clearsMessage() async throws {
        // Arrange: use a tiny delay (10ms = 10_000_000 ns)
        try await seedReview(id: "review-001")
        let sut = makeSUT(clipboardSucceeds: true, clipboardAutoDismissDelay: 10_000_000)
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Act
        sut.copyReviewToClipboard()
        XCTAssertEqual(sut.uiState.clipboardMessage, "Copied!", "Message should be set immediately")

        // Wait for auto-dismiss (with margin)
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        XCTAssertNil(sut.uiState.clipboardMessage, "Message should auto-dismiss after the delay")
    }

    /// Calling clearClipboardMessage manually should clear the message and cancel
    /// the auto-dismiss timer.
    func testClearClipboardMessage_clearsImmediately() async throws {
        // Arrange
        try await seedReview(id: "review-001")
        // Use a large delay so auto-dismiss does not fire during this test
        let sut = makeSUT(clipboardSucceeds: true, clipboardAutoDismissDelay: 5_000_000_000)
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        sut.copyReviewToClipboard()
        XCTAssertEqual(sut.uiState.clipboardMessage, "Copied!")

        // Act
        sut.clearClipboardMessage()

        // Assert
        XCTAssertNil(sut.uiState.clipboardMessage, "Message should be cleared immediately")
    }

    /// A second copy should cancel the first auto-dismiss timer and start a new
    /// one. The message after the second call should reflect the second result.
    func testCopyReviewToClipboard_secondCopyCancelsPreviousTimer() async throws {
        // Arrange
        try await seedReview(id: "review-001")
        let sut = makeSUT(clipboardSucceeds: true, clipboardAutoDismissDelay: 10_000_000)
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Act: copy twice in quick succession
        sut.copyReviewToClipboard()
        XCTAssertEqual(sut.uiState.clipboardMessage, "Copied!")
        sut.copyReviewToClipboard()
        XCTAssertEqual(sut.uiState.clipboardMessage, "Copied!")
        XCTAssertEqual(clipboard.setTextCallCount, 2, "Should call clipboard twice")

        // Wait for auto-dismiss from the second call
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        XCTAssertNil(sut.uiState.clipboardMessage, "Second timer should have fired and cleared the message")
    }

    // MARK: - TC-042: Network Error Cache Fallback

    /// TC-042: When a cached review is present and the live sync fails, the
    /// cached review should remain displayed AND syncError should be set.
    func testLoadReview_networkError_cacheStillDisplayedAndSyncErrorSet() async throws {
        // Arrange: seed a cached review
        try await seedReview(
            id: "review-001",
            rating: 3,
            title: "Okay app",
            body: "Could be better"
        )
        // Configure connection to fail on fetchReviews
        connection.fetchReviewsResult = .failure(NSError(
            domain: "TestError", code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "No internet"]
        ))
        let sut = makeSUT()

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Assert: cached review STILL displayed
        XCTAssertNotNil(sut.uiState.review, "Cached review should remain visible on network error")
        XCTAssertEqual(sut.uiState.review?.title, "Okay app")
        XCTAssertEqual(sut.uiState.review?.body, "Could be better")

        // Assert: syncError banner set
        XCTAssertEqual(sut.uiState.syncError, "Sync failed. Showing cached data.")
        XCTAssertFalse(sut.uiState.isLoading)
    }

    /// TC-042 variant: No cached review AND network fails -> different error message.
    func testLoadReview_noCacheAndNetworkFails_failedToLoadMessage() async throws {
        // Arrange: no review in storage, connection fails
        connection.fetchReviewsResult = .failure(NSError(
            domain: "TestError", code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "No internet"]
        ))
        let sut = makeSUT()

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-missing", appId: "app-001", accountId: "acc-001")

        // Assert
        XCTAssertNil(sut.uiState.review, "No review should be displayed")
        XCTAssertEqual(sut.uiState.syncError, "Failed to load review.")
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - Guard: Missing Connection

    /// loadReviewIfNeeded with nil connection should load from cache only and
    /// NOT set any error (connection is optional for offline-only mode).
    func testLoadReview_noConnection_loadsCacheOnly() async throws {
        // Arrange
        try await seedReview(id: "review-001", rating: 5, title: "Cached")
        let sut = makeSUT(withConnection: false)

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Assert: cached review loaded, no error
        XCTAssertNotNil(sut.uiState.review)
        XCTAssertEqual(sut.uiState.review?.title, "Cached")
        XCTAssertNil(sut.uiState.syncError, "No sync error when connection is nil (offline mode)")
        XCTAssertFalse(sut.uiState.isLoading)
    }

    /// sendReply with nil connection should set replyError immediately.
    func testSendReply_noConnection_setsError() async throws {
        try await seedReview(id: "review-001")
        let sut = makeSUT(withConnection: false)
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        await sut.sendReply(responseBody: "Reply text")

        XCTAssertEqual(sut.uiState.replyError, "No connection available.")
        XCTAssertFalse(sut.uiState.isReplyPending)
        XCTAssertEqual(connection.upsertReplyCallCount, 0,
                       "Should not call connection when none is provided")
    }

    /// deleteReply with nil connection should set replyError immediately.
    func testDeleteReply_noConnection_setsError() async throws {
        try await seedReview(
            id: "review-001",
            responseId: "resp-001",
            responseBody: "Reply"
        )
        let sut = makeSUT(withConnection: false)
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        await sut.deleteReply()

        XCTAssertEqual(sut.uiState.replyError, "No connection available.")
        XCTAssertFalse(sut.uiState.isReplyPending)
        XCTAssertEqual(connection.deleteReplyCallCount, 0,
                       "Should not call connection when none is provided")
    }

    // MARK: - Guard: Missing Review

    /// sendReply without a loaded review should be a no-op (no crash, no error).
    func testSendReply_noReview_noOp() async {
        let sut = makeSUT()
        // Do NOT load any review

        await sut.sendReply(responseBody: "No review loaded")

        XCTAssertNil(sut.uiState.replyError, "No error should be set when there is no review")
        XCTAssertFalse(sut.uiState.isReplyPending)
        XCTAssertEqual(connection.upsertReplyCallCount, 0)
    }

    /// deleteReply without a loaded review should be a no-op (no crash).
    func testDeleteReply_noReview_noOp() async {
        let sut = makeSUT()
        // Do NOT load any review

        await sut.deleteReply()

        XCTAssertNil(sut.uiState.replyError)
        XCTAssertFalse(sut.uiState.isReplyPending)
        XCTAssertEqual(connection.deleteReplyCallCount, 0)
    }

    /// deleteReply in create mode (no existing reply) should be a no-op.
    func testDeleteReply_createMode_noOp() async throws {
        try await seedReview(id: "review-001", responseId: nil)
        let sut = makeSUT()
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")
        XCTAssertEqual(sut.uiState.replyMode, .create)

        await sut.deleteReply()

        XCTAssertNil(sut.uiState.replyError)
        XCTAssertEqual(connection.deleteReplyCallCount, 0,
                       "Should not call deleteReply when there is no existing response")
    }

    /// copyReviewToClipboard without a loaded review should be a no-op.
    func testCopyReviewToClipboard_noReview_noOp() {
        let sut = makeSUT()
        // Do NOT load any review

        sut.copyReviewToClipboard()

        XCTAssertNil(sut.uiState.clipboardMessage, "No message when no review is loaded")
        XCTAssertEqual(clipboard.setTextCallCount, 0, "Should not call clipboard when no review")
    }

    // MARK: - Live Sync Updates Cached Review

    /// loadReviewIfNeeded should update the cached review when live sync returns
    /// a matching review (verifying the sync path works end-to-end).
    func testLoadReview_liveSyncUpdatesCache() async throws {
        // Arrange: seed a stale cached review
        try await seedReview(
            id: "review-001",
            rating: 3,
            title: "Old title",
            body: "Old body"
        )

        // Configure connection to return an updated review
        let updatedReview = CustomerReviewModel(
            id: "review-001",
            rating: 5,
            title: "Updated title",
            body: "Updated body",
            reviewerNickname: "UpdatedUser"
        )
        configureConnectionWithReview(updatedReview)
        let sut = makeSUT()

        // Act
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Assert: uiState reflects the live-synced review
        XCTAssertEqual(sut.uiState.review?.title, "Updated title")
        XCTAssertEqual(sut.uiState.review?.body, "Updated body")
        XCTAssertEqual(sut.uiState.review?.rating, 5)
        XCTAssertNil(sut.uiState.syncError)

        // Assert: storage updated
        let saved = try await storage.fetch(CustomerReviewModel.self, id: "review-001")
        XCTAssertEqual(saved?.title, "Updated title")
    }

    // MARK: - Clipboard Formatted Text Edge Cases

    /// Copy a review with minimal fields (no title, no body, no nickname, no
    /// territory, no date). Should not crash and should produce valid output.
    func testCopyReviewToClipboard_minimalReview_nocrash() async throws {
        let review = CustomerReviewModel(
            id: "review-min",
            rating: 1
        )
        try await storage.save(review, id: "review-min")
        let sut = makeSUT(clipboardSucceeds: true)
        await sut.loadReviewIfNeeded(reviewId: "review-min", appId: "app-001", accountId: "acc-001")

        // Act
        sut.copyReviewToClipboard()

        // Assert
        XCTAssertEqual(sut.uiState.clipboardMessage, "Copied!")
        let copiedText = clipboard.lastSetText!
        // Should have 1 filled star + 4 empty stars
        XCTAssertTrue(copiedText.contains("\u{2605}\u{2606}\u{2606}\u{2606}\u{2606}"),
                      "Should show 1 filled + 4 empty stars for rating 1")
    }

    /// Copy a review with 5-star rating: verify all stars are filled.
    func testCopyReviewToClipboard_fiveStars_allFilled() async throws {
        let review = CustomerReviewModel(
            id: "review-5star",
            rating: 5,
            title: "Perfect"
        )
        try await storage.save(review, id: "review-5star")
        let sut = makeSUT(clipboardSucceeds: true)
        await sut.loadReviewIfNeeded(reviewId: "review-5star", appId: "app-001", accountId: "acc-001")

        sut.copyReviewToClipboard()

        let copiedText = clipboard.lastSetText!
        let allFilled = String(repeating: "\u{2605}", count: 5)
        XCTAssertTrue(copiedText.hasPrefix(allFilled), "5-star rating should show all filled stars")
    }

    // MARK: - loadReviewIfNeeded Clears Previous Errors

    /// Calling loadReviewIfNeeded should clear any previous syncError and
    /// replyError (fresh load resets error state).
    func testLoadReview_clearsPreviousErrors() async throws {
        try await seedReview(id: "review-001")
        let sut = makeSUT()

        // Manually set errors to simulate leftover state
        // (Using a first load with network failure, then retrying)
        connection.fetchReviewsResult = .failure(NSError(domain: "Test", code: 1, userInfo: nil))
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")
        XCTAssertNotNil(sut.uiState.syncError, "Should have syncError after failed load")

        // Retry with success
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )
        await sut.loadReviewIfNeeded(reviewId: "review-001", appId: "app-001", accountId: "acc-001")

        // Assert: errors cleared
        XCTAssertNil(sut.uiState.syncError, "syncError should be cleared on retry")
        XCTAssertNil(sut.uiState.replyError, "replyError should be cleared on retry")
    }
}
