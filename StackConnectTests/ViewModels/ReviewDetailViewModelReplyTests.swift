import XCTest
import StackCoreRust
@testable import StackConnect

/// Replying from the review detail through the reviews provider seam, for
/// Google Play (real service over a mock connection) and App Store (mock service).
@MainActor
final class ReviewDetailViewModelReplyTests: XCTestCase {

    private let compositeId = "com.example.app/gp:review-1"
    private let playAccount = AccountModel(name: "Play Team", providerType: .googlePlay)

    private func playReview(reply: String? = nil) -> CustomerReviewModel {
        CustomerReviewModel(
            id: compositeId,
            rating: 4,
            body: "Nice",
            responseId: reply == nil ? nil : compositeId,
            responseBody: reply
        )
    }

    private func makePlaySUT(
        review: CustomerReviewModel,
        connection: MockGooglePlayAccountConnection,
        account: AccountModel? = nil
    ) -> ReviewDetailViewModel {
        ReviewDetailViewModel(
            review: review,
            appName: "Example",
            account: account ?? playAccount,
            service: GooglePlayCustomerReviewsService(connection: connection)
        )
    }

    // MARK: - Google Play

    func testPlayReplyPassesTheOpaqueIdAndUpdatesTheReview() async {
        let connection = MockGooglePlayAccountConnection()
        let sut = makePlaySUT(review: playReview(), connection: connection)
        sut.uiState.showReplySheet = true

        await sut.submitReply(body: "Thanks!")

        XCTAssertEqual(connection.replies.map(\.reviewId), [compositeId])
        XCTAssertEqual(sut.uiState.review.responseBody, "Thanks!")
        XCTAssertEqual(sut.uiState.review.responseId, compositeId)
        XCTAssertNil(sut.uiState.review.responseState)
        XCTAssertFalse(sut.uiState.showReplySheet)
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Reply sent"))
    }

    /// Google replies are upserts: editing replies again, with no delete.
    func testPlayEditReplacesTheReplyWithASingleCall() async {
        let connection = MockGooglePlayAccountConnection()
        let sut = makePlaySUT(review: playReview(reply: "Old"), connection: connection)
        sut.startEditingReply()
        XCTAssertEqual(sut.uiState.replyText, "Old")

        await sut.submitReply(body: "New")

        XCTAssertEqual(connection.replies.count, 1)
        XCTAssertEqual(sut.uiState.review.responseBody, "New")
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Reply updated"))
    }

    func testPlayRejectedReplyStaysInTheComposerWithGooglesReason() async {
        let connection = MockGooglePlayAccountConnection()
        connection.replyHandler = { _, _ in throw StackError.Http(status: 400, message: "too long") }
        let sut = makePlaySUT(review: playReview(), connection: connection)
        sut.uiState.showReplySheet = true

        await sut.submitReply(body: String(repeating: "a", count: 400))

        XCTAssertTrue(sut.uiState.showReplySheet)
        XCTAssertEqual(
            sut.uiState.replyError,
            String(localized: "Google Play rejected this reply. Replies are limited to about \(GooglePlayReviewLimits.replyCharacterLimit) characters — shorten it and try again.")
        )
        XCTAssertNil(sut.uiState.review.responseBody)

        sut.cancelReplySheet()
        XCTAssertNil(sut.uiState.replyError)
    }

    func testPlayNoAccessToReplyKeepsTheCoresDetail() async {
        let detail = "The service account can't reply to reviews of com.example.app. Grant it \"Reply to reviews\" in Play Console."
        let connection = MockGooglePlayAccountConnection()
        connection.replyHandler = { _, _ in throw StackError.Auth(message: detail) }
        let sut = makePlaySUT(review: playReview(), connection: connection)

        await sut.submitReply(body: "Thanks")

        XCTAssertEqual(sut.uiState.replyError, String(localized: "Google Play denied access to this service account.") + "\n" + detail)
    }

    func testPlayReplyIsGatedByTheReviewEditRule() async {
        let connection = MockGooglePlayAccountConnection()
        let viewOnly = AccountModel(
            name: "Imported",
            providerType: .googlePlay,
            rules: AccountRules(apps: [.view], review: [.view]),
            origin: .imported
        )
        let sut = makePlaySUT(review: playReview(), connection: connection, account: viewOnly)

        XCTAssertFalse(sut.uiState.canReply)
        await sut.submitReply(body: "Thanks")

        XCTAssertTrue(connection.replies.isEmpty)
        XCTAssertNil(sut.uiState.review.responseBody)
    }

    func testPlayNeverOffersOrPerformsReplyDeletion() async {
        let connection = MockGooglePlayAccountConnection()
        let sut = makePlaySUT(review: playReview(reply: "Thanks"), connection: connection)

        XCTAssertFalse(sut.uiState.canDeleteReply, "Even with every review rule")
        await sut.deleteResponse()

        XCTAssertEqual(sut.uiState.review.responseBody, "Thanks")
        XCTAssertEqual(sut.uiState.traits, .googlePlay)
    }

    // MARK: - App Store

    func testAppStoreEditAsksTheStoreToReplaceTheExistingResponse() async {
        let service = MockCustomerReviewsService()
        let sut = ReviewDetailViewModel(
            review: CustomerReviewModel(id: "asc-1", rating: 3, responseId: "resp-old", responseBody: "Old"),
            appName: "App",
            account: AccountModel(name: "Team", providerType: .apple),
            service: service
        )
        sut.startEditingReply()

        await sut.submitReply(body: "New")

        XCTAssertEqual(service.replyRequests, [.init(reviewId: "asc-1", body: "New", replacingResponseId: "resp-old")])
        XCTAssertEqual(sut.uiState.review.responseId, "resp-asc-1")
        XCTAssertEqual(sut.uiState.review.responseState, "PENDING_PUBLISH")
    }

    func testAppStoreDeleteNeedsTheDeleteRule() async {
        let service = MockCustomerReviewsService()
        let review = CustomerReviewModel(id: "asc-1", rating: 3, responseId: "resp-1", responseBody: "Thanks")
        let editor = AccountModel(name: "Imported", providerType: .apple, rules: AccountRules(review: [.view, .edit]), origin: .imported)

        let restricted = ReviewDetailViewModel(review: review, appName: "App", account: editor, service: service)
        XCTAssertFalse(restricted.uiState.canDeleteReply)
        await restricted.deleteResponse()
        XCTAssertTrue(service.deletedResponseIds.isEmpty)

        let full = ReviewDetailViewModel(review: review, appName: "App", account: AccountModel(name: "Team", providerType: .apple), service: service)
        XCTAssertTrue(full.uiState.canDeleteReply)
        await full.deleteResponse()
        XCTAssertEqual(service.deletedResponseIds, ["resp-1"])
        XCTAssertNil(full.uiState.review.responseBody)
    }

    // MARK: - Offline cache (N5)

    func testPlayReplyAlsoUpdatesTheCachedReview() async {
        let storage = MockPersistentStorable()
        let cache = GooglePlayCustomerReviewsCache(storage: storage, accountId: playAccount.id, packageName: "com.example.app")
        await cache.saveReviews([playReview(), CustomerReviewModel(id: "com.example.app/other", rating: 2)])
        let sut = ReviewDetailViewModel(
            review: playReview(),
            appName: "Example",
            account: playAccount,
            service: GooglePlayCustomerReviewsService(connection: MockGooglePlayAccountConnection()),
            cache: cache
        )

        await sut.submitReply(body: "Thanks!")

        let cached = await cache.cachedReviews()
        XCTAssertEqual(cached?.first?.responseBody, "Thanks!")
        XCTAssertEqual(cached?.first?.responseId, compositeId)
        XCTAssertNil(cached?.last?.responseBody, "Other reviews are untouched")
    }

    func testFailedReplyLeavesTheCacheAlone() async {
        let storage = MockPersistentStorable()
        let cache = GooglePlayCustomerReviewsCache(storage: storage, accountId: playAccount.id, packageName: "com.example.app")
        await cache.saveReviews([playReview()])
        let connection = MockGooglePlayAccountConnection()
        connection.replyHandler = { _, _ in throw StackError.Http(status: 404, message: "") }
        let sut = ReviewDetailViewModel(
            review: playReview(),
            appName: "Example",
            account: playAccount,
            service: GooglePlayCustomerReviewsService(connection: connection),
            cache: cache
        )

        await sut.submitReply(body: "Thanks!")

        XCTAssertEqual(sut.uiState.replyError, String(localized: "This review is no longer available on Google Play."))
        let cached = await cache.cachedReviews()
        XCTAssertNil(cached?.first?.responseBody)
    }

    // MARK: - Composer dismissal (N2)

    /// Also what swiping the composer away does: the next reply starts clean,
    /// not in edit mode with the old draft and error.
    func testCancelReplySheetDropsDraftErrorAndEditMode() {
        let sut = makePlaySUT(review: playReview(reply: "Old"), connection: MockGooglePlayAccountConnection())
        sut.startEditingReply()
        sut.uiState.replyText = "Half-edited"
        sut.uiState.replyError = "Earlier failure"

        sut.cancelReplySheet()

        XCTAssertFalse(sut.uiState.showReplySheet)
        XCTAssertFalse(sut.uiState.isEditingReply)
        XCTAssertEqual(sut.uiState.replyText, "")
        XCTAssertNil(sut.uiState.replyError)
    }

    /// The composer can go away while an edit is being sent: the toast still
    /// reports an update, not a new reply.
    func testEditReportedAsUpdateEvenIfTheComposerClosesMidSend() async {
        let gate = AsyncGate()
        let connection = MockGooglePlayAccountConnection()
        connection.replyHandler = { reviewId, body in
            await gate.wait()
            return CustomerReviewResponseModel(id: reviewId, body: body, state: nil, date: Date())
        }
        let sut = makePlaySUT(review: playReview(reply: "Old"), connection: connection)
        sut.startEditingReply()

        let send = Task { await sut.submitReply(body: "New") }
        await gate.waitForArrivals()
        sut.cancelReplySheet()
        await gate.open()
        await send.value

        XCTAssertEqual(sut.uiState.review.responseBody, "New")
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Reply updated"))
    }

    func testMissingServiceSendsNothing() async {
        let sut = ReviewDetailViewModel(
            review: playReview(),
            appName: "Example",
            account: playAccount,
            service: nil
        )

        await sut.submitReply(body: "Thanks")

        XCTAssertNil(sut.uiState.review.responseBody)
        XCTAssertFalse(sut.uiState.isSending)
    }
}
