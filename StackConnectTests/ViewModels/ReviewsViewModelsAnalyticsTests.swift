import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics events of Ratings & Reviews, Review detail / reply, All Reviews and
/// Reply templates. Never asserts (or sends) review or template text.
@MainActor
final class ReviewsViewModelsAnalyticsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    private var account: AccountModel { AccountModel(id: "acc1", name: "Team", providerType: .apple) }

    // MARK: - Ratings & Reviews

    private func makeRatingsSUT() -> RatingsReviewsViewModel {
        RatingsReviewsViewModel(
            appId: "app-1",
            bundleId: "com.example.app",
            account: account,
            service: nil,
            ratingSummaryFetcher: MockAppStoreRatingSummaryFetcher(),
            analytics: analytics
        )
    }

    func testReplyTracksTapAndFailureWithoutService() async {
        let sut = makeRatingsSUT()

        await sut.reply(to: CustomerReviewModel(id: "r1", rating: 4), body: "Private reply text")

        XCTAssertEqual(analytics.taps(of: .send), [.buttonTap(.send, on: .reviewReply)])
        XCTAssertEqual(analytics.actions(of: .replyToReview), [.action(.replyToReview, on: .reviewReply, result: .failure)])
    }

    func testDeleteResponseTracksTapAndFailureWithoutService() async {
        let sut = makeRatingsSUT()

        await sut.deleteResponse(for: CustomerReviewModel(id: "r1", rating: 2, responseId: "resp-1"))

        XCTAssertEqual(analytics.taps(of: .delete), [.buttonTap(.delete, on: .ratingsReviews)])
        XCTAssertEqual(analytics.actions(of: .deleteReviewResponse), [.action(.deleteReviewResponse, on: .ratingsReviews, result: .failure)])
    }

    func testDeleteResponseWithoutResponseTracksTapOnly() async {
        let sut = makeRatingsSUT()

        await sut.deleteResponse(for: CustomerReviewModel(id: "r1", rating: 2))

        XCTAssertEqual(analytics.taps(of: .delete).count, 1)
        XCTAssertTrue(analytics.actions(of: .deleteReviewResponse).isEmpty)
    }

    func testApplyFilterTracksStarRatingOnly() async {
        let sut = makeRatingsSUT()

        await sut.applyFilter(rating: 3)
        await sut.applyFilter(rating: nil)

        XCTAssertEqual(analytics.actions(of: .filterReviews), [
            .action(.filterReviews, on: .ratingsReviews, result: .failure, parameters: [AnalyticsParameterKey.rating: .int(3)]),
            .action(.filterReviews, on: .ratingsReviews, result: .failure)
        ])
    }

    // MARK: - Review detail

    private func makeDetailSUT(review: CustomerReviewModel) -> ReviewDetailViewModel {
        ReviewDetailViewModel(
            review: review,
            appName: "App",
            account: account,
            service: nil,
            analytics: analytics
        )
    }

    func testSubmitNewReplyTracksSendAndFailureWithoutService() async {
        let sut = makeDetailSUT(review: CustomerReviewModel(id: "r1", rating: 5))

        await sut.submitReply(body: "Thanks!")

        XCTAssertEqual(analytics.taps(of: .send), [.buttonTap(.send, on: .reviewReply)])
        XCTAssertEqual(analytics.actions(of: .replyToReview), [.action(.replyToReview, on: .reviewReply, result: .failure)])
        XCTAssertTrue(analytics.actions(of: .updateReviewReply).isEmpty)
    }

    func testSubmitEditedReplyTracksSaveAndUpdateFailure() async {
        let sut = makeDetailSUT(review: CustomerReviewModel(id: "r1", rating: 5, responseId: "resp-1", responseBody: "Old"))
        sut.startEditingReply()

        await sut.submitReply(body: "New")

        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .reviewReply)])
        XCTAssertEqual(analytics.actions(of: .updateReviewReply), [.action(.updateReviewReply, on: .reviewReply, result: .failure)])
    }

    func testDeleteResponseTracksConfirmAndFailureWithoutService() async {
        let sut = makeDetailSUT(review: CustomerReviewModel(id: "r1", rating: 5, responseId: "resp-1", responseBody: "Old"))

        await sut.deleteResponse()

        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .reviewDetail)])
        XCTAssertEqual(analytics.actions(of: .deleteReviewResponse), [.action(.deleteReviewResponse, on: .reviewDetail, result: .failure)])
    }

    // MARK: - All Reviews

    func testAllReviewsLoadTracksNothing() async {
        let sut = AllReviewsViewModel(storage: MockPersistentStorable(), analytics: analytics)

        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testAllReviewsRefreshTracksSuccessOffline() async {
        let sut = AllReviewsViewModel(
            storage: MockPersistentStorable(),
            syncService: SyncService(storage: MockPersistentStorable(), keychain: MockKeyStorable()),
            analytics: analytics
        )

        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .allReviews, result: .success)])
    }

    func testAllReviewsRefreshTracksFailureWhenStorageFails() async {
        let storage = MockPersistentStorable()
        await storage.failFetchAll(AppModel.self)
        let sut = AllReviewsViewModel(
            storage: storage,
            syncService: SyncService(storage: MockPersistentStorable(), keychain: MockKeyStorable()),
            analytics: analytics
        )

        await sut.refresh()

        XCTAssertEqual(analytics.results(of: .refresh), [.failure])
    }

    // MARK: - Reply templates

    private func makeTemplatesSUT(storage: MockPersistentStorable) -> ReplyTemplatesViewModel {
        ReplyTemplatesViewModel(accountId: "acc1", storage: storage, analytics: analytics)
    }

    func testSaveTemplateTracksTapAndSuccess() async {
        let sut = makeTemplatesSUT(storage: MockPersistentStorable())

        await sut.save(title: "Thanks", body: "Thank you for the review")

        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .replyTemplateForm)])
        XCTAssertEqual(analytics.actions(of: .createReplyTemplate), [.action(.createReplyTemplate, on: .replyTemplateForm, result: .success)])
    }

    func testSaveTemplateTracksFailureWhenStorageFails() async {
        let storage = MockPersistentStorable()
        await storage.failSave(ReplyTemplateModel.self)
        let sut = makeTemplatesSUT(storage: storage)

        await sut.save(title: "Thanks", body: "Body")

        XCTAssertEqual(analytics.results(of: .createReplyTemplate), [.failure])
    }

    func testUpdateAndDeleteTemplateTrackTapsAndSuccess() async {
        let sut = makeTemplatesSUT(storage: MockPersistentStorable())
        let template = ReplyTemplateModel(accountId: "acc1", title: "T", body: "B")

        await sut.update(template, title: "T2", body: "B2")
        await sut.delete(template)

        XCTAssertEqual(analytics.actions(of: .updateReplyTemplate), [.action(.updateReplyTemplate, on: .replyTemplateForm, result: .success)])
        XCTAssertEqual(analytics.taps(of: .delete), [.buttonTap(.delete, on: .replyTemplates)])
        XCTAssertEqual(analytics.actions(of: .deleteReplyTemplate), [.action(.deleteReplyTemplate, on: .replyTemplates, result: .success)])
    }

    func testDeleteTemplateTracksFailureWhenStorageFails() async {
        let storage = MockPersistentStorable()
        let template = ReplyTemplateModel(accountId: "acc1", title: "T", body: "B")
        await storage.failDelete(ReplyTemplateModel.self, id: template.id)
        let sut = makeTemplatesSUT(storage: storage)

        await sut.delete(template)

        XCTAssertEqual(analytics.results(of: .deleteReplyTemplate), [.failure])
    }
}
