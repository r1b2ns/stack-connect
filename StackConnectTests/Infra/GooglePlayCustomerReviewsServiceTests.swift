import XCTest
import StackCoreRust
@testable import StackConnect

/// The Google Play side of the reviews provider seam.
final class GooglePlayCustomerReviewsServiceTests: XCTestCase {

    private var connection: MockGooglePlayAccountConnection!
    private var sut: GooglePlayCustomerReviewsService!

    override func setUp() {
        super.setUp()
        connection = MockGooglePlayAccountConnection()
        sut = GooglePlayCustomerReviewsService(connection: connection)
    }

    override func tearDown() {
        sut = nil
        connection = nil
        super.tearDown()
    }

    func testTraitsAreGooglePlays() {
        XCTAssertEqual(sut.traits, .googlePlay)
        XCTAssertEqual(sut.traits.sortOptions, [.newest], "Google only serves newest first")
        XCTAssertFalse(sut.traits.canDeleteReplies)
        XCTAssertFalse(sut.traits.showsStoreRatingSummary)
        XCTAssertEqual(sut.traits.replyCharacterLimit, 350)
        XCTAssertNotNil(sut.traits.listNote, "The recent-reviews limit is explained")
    }

    func testFetchPassesPackageFilterLimitAndTokenThrough() async throws {
        connection.fetchReviewsPageHandler = { _ in
            CustomerReviewsPageModel(reviews: [CustomerReviewModel(id: "com.example.app/r1", rating: 5)], nextPageToken: "next")
        }

        let page = try await sut.fetchReviewsPage(
            appId: "com.example.app",
            sort: .newest,
            filterRating: 2,
            limit: 50,
            pageToken: "token-1"
        )

        XCTAssertEqual(page.reviews.map(\.id), ["com.example.app/r1"])
        XCTAssertEqual(page.nextPageToken, "next")
        XCTAssertEqual(connection.reviewsPageRequests, [
            .init(packageName: "com.example.app", filterRating: 2, limit: 50, pageToken: "token-1")
        ])
    }

    func testReplyIsAnUpsertWithTheOpaqueIdAndNoExtraCall() async throws {
        let response = try await sut.reply(
            toReviewId: "com.example.app/r1",
            body: "Thanks!",
            replacingResponseId: "com.example.app/r1"
        )

        XCTAssertEqual(connection.replies.map(\.reviewId), ["com.example.app/r1"], "Passed back unchanged, once")
        XCTAssertEqual(connection.replies.map(\.body), ["Thanks!"])
        XCTAssertEqual(response.id, "com.example.app/r1")
        XCTAssertEqual(response.body, "Thanks!")
        XCTAssertNil(response.state, "Play replies have no moderation state")
        XCTAssertNotNil(response.date)
    }

    func testDeleteReplyIsUnsupported() async {
        do {
            try await sut.deleteReply(responseId: "com.example.app/r1")
            XCTFail("Expected Unsupported")
        } catch StackError.Unsupported {
            // Expected.
        } catch {
            XCTFail("Expected StackError.Unsupported, got \(error)")
        }
    }

    func testReplyErrorsUseTheReplyCopy() {
        let tooLong = StackError.Http(status: 400, message: "too long")

        XCTAssertEqual(
            sut.message(for: tooLong, operation: .reply),
            GooglePlayErrorTranslator.friendlyMessage(for: tooLong, operation: .replyToReview)
        )
        XCTAssertEqual(
            sut.message(for: tooLong, operation: .load),
            GooglePlayErrorTranslator.friendlyMessage(for: tooLong)
        )
    }

    /// Replying to a review that left Google's window (or was deleted) says so;
    /// a 404 while listing still points at the package name.
    func testNotFoundCopyDependsOnTheOperation() {
        let notFound = StackError.Http(status: 404, message: "")

        XCTAssertEqual(
            sut.message(for: notFound, operation: .reply),
            String(localized: "This review is no longer available on Google Play.")
        )
        XCTAssertEqual(
            sut.message(for: notFound, operation: .load),
            String(localized: "Google Play found no app with this package name. Check it in Play Console and try again.")
        )
    }

    // MARK: - Cache

    func testCacheRoundTripsTheFirstPagePerAccountAndPackage() async {
        let storage = MockPersistentStorable()
        let cache = GooglePlayCustomerReviewsCache(storage: storage, accountId: "acc", packageName: "com.example.app")
        let other = GooglePlayCustomerReviewsCache(storage: storage, accountId: "acc", packageName: "com.other.app")

        let empty = await cache.cachedReviews()
        await cache.saveReviews([CustomerReviewModel(id: "com.example.app/r1", rating: 3)])
        let cached = await cache.cachedReviews()
        let otherCached = await other.cachedReviews()

        XCTAssertNil(empty)
        XCTAssertEqual(cached?.map(\.id), ["com.example.app/r1"])
        XCTAssertNil(otherCached, "Scoped per package")
    }
}
