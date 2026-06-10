import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsRatingsReviewsModel` (T-W16).
///
/// Covers:
/// - TC-023: Load aggregate card happy path
/// - TC-024: iTunes failure graceful fallback (aggregate nil, reviews still load)
/// - TC-025: Page 1 reviews + canLoadMore
/// - TC-026: Load More appends (3+2=5), canLoadMore updated, isLoadingMore toggles
/// - TC-027: Final page → Load More hidden
/// - TC-029: Empty reviews → empty state, no Load More
/// - TC-080: Cursor not persisted; fresh instance reloads page 1
@MainActor
final class WindowsRatingsReviewsModelTests: XCTestCase {

    private var storage: MockStorage!
    private var connection: MockAppleConnection!
    private var lookupNetworking: MockLookupNetworking!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorage()
        connection = MockAppleConnection()
        lookupNetworking = MockLookupNetworking()
    }

    override func tearDown() async throws {
        storage = nil
        connection = nil
        lookupNetworking = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a SUT with the shared test dependencies.
    private func makeSUT(
        withConnection: Bool = true,
        lookupNetworking: MockLookupNetworking? = nil
    ) -> WindowsRatingsReviewsModel {
        let networking = lookupNetworking ?? self.lookupNetworking!
        let lookupService = ITunesLookupService(
            networking: networking,
            storage: storage,
            cacheTTL: 3600
        )
        return WindowsRatingsReviewsModel(
            storage: storage,
            connection: withConnection ? connection : nil,
            lookupService: lookupService
        )
    }

    /// Creates a test review with deterministic data.
    private func makeReview(
        id: String = "review-001",
        rating: Int = 5,
        title: String? = "Great app",
        body: String? = "Love it!",
        nickname: String? = "JohnDoe",
        date: Date? = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> CustomerReviewModel {
        CustomerReviewModel(
            id: id,
            rating: rating,
            title: title,
            body: body,
            reviewerNickname: nickname,
            createdDate: date
        )
    }

    /// Seeds a successful iTunes Lookup response for the given country.
    private func seedLookupResponse(
        bundleId: String,
        country: String,
        averageRating: Double,
        ratingCount: Int
    ) {
        let url = "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=\(country)"
        let json = """
        {"resultCount": 1, "results": [{"averageUserRating": \(averageRating), "userRatingCount": \(ratingCount)}]}
        """
        lookupNetworking.responses[url] = .success(Data(json.utf8))
    }

    // MARK: - TC-023: Load aggregate card happy path

    /// Verifies that aggregate rating data (average, totalCount, storefrontCount)
    /// is loaded successfully and exposed through uiState.
    func testTC023_LoadAggregateCardHappyPath() async {
        // Given: iTunes Lookup returns data for 2 storefronts
        seedLookupResponse(bundleId: "com.example.app", country: "us", averageRating: 4.5, ratingCount: 10000)
        seedLookupResponse(bundleId: "com.example.app", country: "gb", averageRating: 4.0, ratingCount: 5000)

        // And: Reviews return empty (we only care about the rating here)
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()

        // When
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: aggregate rating is populated (AC-W10-1)
        let aggregate = sut.uiState.aggregateRating
        XCTAssertNotNil(aggregate, "Aggregate rating should be populated")
        XCTAssertEqual(aggregate?.storefrontCount, 2)
        XCTAssertEqual(aggregate?.totalCount, 15000)

        // Weighted average: (4.5*10000 + 4.0*5000) / 15000 = 65000/15000 ≈ 4.333
        let expectedAvg = 65000.0 / 15000.0
        XCTAssertEqual(aggregate!.averageRating, expectedAvg, accuracy: 0.01)

        // No rating error
        XCTAssertNil(sut.uiState.ratingError)
        // Loading finished
        XCTAssertFalse(sut.uiState.isLoadingRating)
    }

    // MARK: - TC-024: iTunes failure graceful fallback

    /// Verifies that when the iTunes lookup fails, aggregate is nil and
    /// ratingError is set, but reviews still load successfully (AC-W10-2, AC-W10-3).
    func testTC024_ITunesFailureGracefulFallback() async {
        // Given: All iTunes Lookup requests fail (total network failure)
        lookupNetworking.shouldThrowAll = true

        // And: Reviews return successfully
        let reviews = [
            makeReview(id: "r1", rating: 5, title: "Awesome"),
            makeReview(id: "r2", rating: 4, title: "Good"),
        ]
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: reviews, hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()

        // When
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: aggregate is nil with error (AC-W10-3)
        XCTAssertNil(sut.uiState.aggregateRating, "Aggregate should be nil on iTunes failure")
        XCTAssertEqual(sut.uiState.ratingError, "Rating unavailable")

        // But: reviews are loaded successfully (AC-W10-2: independent)
        XCTAssertEqual(sut.uiState.reviews.count, 2)
        XCTAssertEqual(sut.uiState.reviews[0].id, "r1")
        XCTAssertEqual(sut.uiState.reviews[1].id, "r2")
        XCTAssertNil(sut.uiState.reviewsError)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - TC-025: Page 1 reviews + cursor + canLoadMore

    /// Verifies that loading the first page populates reviews, captures the
    /// cursor, and sets canLoadMore correctly (AC-W11-3).
    func testTC025_FirstPageReviewsWithCursorAndCanLoadMore() async {
        // Given: First page returns 3 reviews with a next-page cursor
        let reviews = [
            makeReview(id: "r1", rating: 5),
            makeReview(id: "r2", rating: 4),
            makeReview(id: "r3", rating: 3),
        ]
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: reviews, hasNextPage: true, cursor: "page2-cursor")
        )

        let sut = makeSUT()

        // When
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: reviews populated
        XCTAssertEqual(sut.uiState.reviews.count, 3)
        XCTAssertEqual(sut.uiState.reviews[0].id, "r1")
        XCTAssertEqual(sut.uiState.reviews[1].id, "r2")
        XCTAssertEqual(sut.uiState.reviews[2].id, "r3")

        // Load More visible (cursor is private; view uses canLoadMore)
        XCTAssertTrue(sut.uiState.canLoadMore)

        // Loading finished
        XCTAssertFalse(sut.uiState.isLoading)

        // Each review has accessible fields (AC-W11-1/AC-W11-6 data availability)
        let firstReview = sut.uiState.reviews[0]
        XCTAssertEqual(firstReview.rating, 5)
        XCTAssertNotNil(firstReview.title)
        XCTAssertNotNil(firstReview.body)
        XCTAssertNotNil(firstReview.reviewerNickname)
        XCTAssertNotNil(firstReview.createdDate)
        XCTAssertNotNil(firstReview.id)
    }

    // MARK: - TC-026: Load More appends (3+2=5), cursor updated, isLoadingMore toggles

    /// Verifies that Load More appends new reviews, updates the cursor, and
    /// toggles isLoadingMore (AC-W11-2).
    func testTC026_LoadMoreAppendsReviewsAndUpdatesCursor() async {
        // Given: First page returns 3 reviews with cursor
        let page1Reviews = [
            makeReview(id: "r1", rating: 5),
            makeReview(id: "r2", rating: 4),
            makeReview(id: "r3", rating: 3),
        ]
        let page2Reviews = [
            makeReview(id: "r4", rating: 2),
            makeReview(id: "r5", rating: 1),
        ]

        connection.fetchReviewsResultQueue = [
            .success(ReviewsPage(reviews: page1Reviews, hasNextPage: true, cursor: "page2-cursor")),
            .success(ReviewsPage(reviews: page2Reviews, hasNextPage: false, cursor: nil)),
        ]

        let sut = makeSUT()

        // Load first page
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertEqual(sut.uiState.reviews.count, 3)
        XCTAssertTrue(sut.uiState.canLoadMore)

        // When: Load More
        await sut.loadNextPage(appId: "app-001")

        // Then: reviews appended (3+2=5)
        XCTAssertEqual(sut.uiState.reviews.count, 5)
        XCTAssertEqual(sut.uiState.reviews[0].id, "r1")
        XCTAssertEqual(sut.uiState.reviews[1].id, "r2")
        XCTAssertEqual(sut.uiState.reviews[2].id, "r3")
        XCTAssertEqual(sut.uiState.reviews[3].id, "r4")
        XCTAssertEqual(sut.uiState.reviews[4].id, "r5")

        // isLoadingMore back to false
        XCTAssertFalse(sut.uiState.isLoadingMore)

        // Load More hidden (no more pages) — covered by TC-027
        XCTAssertFalse(sut.uiState.canLoadMore)

        // Verify the cursor was passed to the connection
        XCTAssertEqual(connection.lastFetchReviewsCursor, "page2-cursor")
        XCTAssertEqual(connection.fetchReviewsCallCount, 2)
    }

    // MARK: - TC-027: Final page → Load More hidden

    /// Verifies that after loading the final page, canLoadMore is false and
    /// pageToken is nil — Load More should be hidden.
    func testTC027_FinalPageHidesLoadMore() async {
        // Given: First page is also the last page
        let reviews = [
            makeReview(id: "r1", rating: 5),
        ]
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: reviews, hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: no more pages
        XCTAssertFalse(sut.uiState.canLoadMore)

        // Load More call with no cursor is a no-op
        await sut.loadNextPage(appId: "app-001")
        XCTAssertEqual(sut.uiState.reviews.count, 1, "Should not change reviews when no cursor")
        XCTAssertEqual(connection.fetchReviewsCallCount, 1, "Should not call fetchReviews again")
    }

    // MARK: - TC-029: Empty reviews → empty state, no Load More

    /// Verifies that when the API returns zero reviews, the model shows an
    /// empty state with no Load More (AC-W11-4).
    func testTC029_EmptyReviewsProducesEmptyStateNoLoadMore() async {
        // Given: API returns zero reviews
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: empty reviews
        XCTAssertTrue(sut.uiState.reviews.isEmpty)

        // No Load More
        XCTAssertFalse(sut.uiState.canLoadMore)

        // No error
        XCTAssertNil(sut.uiState.reviewsError)

        // Loading finished
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - TC-080: Cursor not persisted; fresh instance reloads page 1

    /// Verifies that the pagination cursor is memory-only. A fresh model
    /// instance starts with canLoadMore = false and reloads page 1 (R4).
    func testTC080_CursorNotPersistedFreshInstanceReloadsPage1() async {
        // Given: First instance loads page 1 with cursor (canLoadMore = true)
        let page1Reviews = [makeReview(id: "r1", rating: 5)]
        connection.fetchReviewsResultQueue = [
            .success(ReviewsPage(reviews: page1Reviews, hasNextPage: true, cursor: "cursor-abc")),
        ]

        let sut1 = makeSUT()
        await sut1.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertTrue(sut1.uiState.canLoadMore, "First instance should have more pages")

        // When: a fresh instance is created
        let page1Again = [makeReview(id: "r1-fresh", rating: 4)]
        connection.fetchReviewsResultQueue = [
            .success(ReviewsPage(reviews: page1Again, hasNextPage: false, cursor: nil)),
        ]

        let sut2 = makeSUT()

        // Then: fresh instance starts with canLoadMore = false (no stale cursor)
        XCTAssertFalse(sut2.uiState.canLoadMore, "Fresh instance must start with canLoadMore = false")

        // And: loading fetches page 1 again (cursor=nil passed to connection)
        await sut2.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertEqual(connection.lastFetchReviewsCursor, nil, "Fresh load must pass nil cursor (page 1)")
        XCTAssertEqual(sut2.uiState.reviews.count, 1)
        XCTAssertEqual(sut2.uiState.reviews[0].id, "r1-fresh")
        XCTAssertFalse(sut2.uiState.canLoadMore, "No more pages after fresh load")
    }

    // MARK: - AC-W10-2: Rating loading state independent of reviews list

    /// Verifies that the rating and reviews loading states are tracked
    /// independently.
    func testACW10_2_RatingAndReviewsLoadingStatesAreIndependent() async {
        // Given: iTunes lookup will fail, but reviews succeed
        lookupNetworking.shouldThrowAll = true
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [makeReview(id: "r1")], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: both loading states are false (both finished)
        XCTAssertFalse(sut.uiState.isLoadingRating)
        XCTAssertFalse(sut.uiState.isLoading)

        // Rating failed independently
        XCTAssertNil(sut.uiState.aggregateRating)
        XCTAssertEqual(sut.uiState.ratingError, "Rating unavailable")

        // Reviews succeeded independently
        XCTAssertEqual(sut.uiState.reviews.count, 1)
        XCTAssertNil(sut.uiState.reviewsError)
    }

    // MARK: - AC-W11-5: First-page failure → non-blocking error + retry

    /// Verifies that when the first page of reviews fails, the error is
    /// non-blocking (rating can still load) and the model supports retry.
    func testACW11_5_FirstPageFailureNonBlockingErrorAndRetry() async {
        // Given: Reviews fail, but rating succeeds
        connection.fetchReviewsResult = .failure(NSError(domain: "net", code: -1))
        seedLookupResponse(bundleId: "com.example.app", country: "us", averageRating: 4.5, ratingCount: 1000)

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: reviews error is set (non-blocking)
        XCTAssertNotNil(sut.uiState.reviewsError)
        XCTAssertEqual(sut.uiState.reviewsError, "Failed to load reviews.")

        // Rating loaded successfully (independent)
        XCTAssertNotNil(sut.uiState.aggregateRating)
        XCTAssertEqual(sut.uiState.aggregateRating?.totalCount, 1000)

        // Loading finished
        XCTAssertFalse(sut.uiState.isLoading)

        // Reviews are empty (no cached reviews in this design)
        XCTAssertTrue(sut.uiState.reviews.isEmpty)

        // When: retry succeeds
        let retryReviews = [makeReview(id: "retry-r1", rating: 5)]
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: retryReviews, hasNextPage: false, cursor: nil)
        )
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: reviews loaded, error cleared
        XCTAssertEqual(sut.uiState.reviews.count, 1)
        XCTAssertEqual(sut.uiState.reviews[0].id, "retry-r1")
        XCTAssertNil(sut.uiState.reviewsError)
    }

    // MARK: - AC-W11-5 (addendum): Keep already-loaded reviews on refresh failure

    /// Verifies that if reviews were previously loaded and a subsequent
    /// load fails, the already-loaded reviews are preserved.
    func testACW11_5_KeepExistingReviewsOnRefreshFailure() async {
        // Given: First load succeeds
        let reviews = [makeReview(id: "r1"), makeReview(id: "r2")]
        connection.fetchReviewsResultQueue = [
            .success(ReviewsPage(reviews: reviews, hasNextPage: false, cursor: nil)),
            .failure(NSError(domain: "net", code: -1)),
        ]

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertEqual(sut.uiState.reviews.count, 2)

        // When: second load (refresh) fails
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: error is set but previously loaded reviews are preserved
        XCTAssertNotNil(sut.uiState.reviewsError)
        XCTAssertEqual(sut.uiState.reviews.count, 2,
                       "Reviews from first load should be preserved on refresh failure")
    }

    // MARK: - Sort/Filter plumbing

    /// Verifies that sort order is passed through to the connection.
    func testSortOrderPassedToConnection() async {
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        sut.setSort(.ratingDescending)
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        XCTAssertEqual(connection.lastFetchReviewsSort, .ratingDescending)
    }

    /// Verifies that filter rating is passed through to the connection.
    func testFilterRatingPassedToConnection() async {
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        sut.setFilterRating(["1", "2"])
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        XCTAssertEqual(connection.lastFetchReviewsFilterRating, ["1", "2"])
    }

    // MARK: - Load More no-op when no cursor

    /// Verifies that loadNextPage is a no-op when there is no cursor.
    func testLoadNextPageNoOpWhenNoCursor() async {
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [makeReview()], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertFalse(sut.uiState.canLoadMore)

        let callCountBefore = connection.fetchReviewsCallCount
        await sut.loadNextPage(appId: "app-001")

        XCTAssertEqual(connection.fetchReviewsCallCount, callCountBefore,
                       "Should not call fetchReviews when no cursor")
    }

    // MARK: - Load More failure sets reviewsError and preserves state

    /// Verifies that when Load More fails, reviewsError is set with a
    /// non-blocking message, existing reviews are preserved, and canLoadMore
    /// remains true so the user can retry.
    func testLoadMoreFailureSetsErrorAndPreservesState() async {
        // Given: First page loads successfully with a next-page cursor
        let page1Reviews = [
            makeReview(id: "r1", rating: 5),
            makeReview(id: "r2", rating: 4),
        ]
        connection.fetchReviewsResultQueue = [
            .success(ReviewsPage(reviews: page1Reviews, hasNextPage: true, cursor: "page2-cursor")),
            .failure(NSError(domain: "net", code: -1)),
        ]

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertEqual(sut.uiState.reviews.count, 2)
        XCTAssertTrue(sut.uiState.canLoadMore)
        XCTAssertNil(sut.uiState.reviewsError)

        // When: Load More fails
        await sut.loadNextPage(appId: "app-001")

        // Then: error is set
        XCTAssertEqual(sut.uiState.reviewsError, "Failed to load more reviews.")

        // Existing reviews preserved
        XCTAssertEqual(sut.uiState.reviews.count, 2, "Existing reviews must not be cleared on Load More failure")
        XCTAssertEqual(sut.uiState.reviews[0].id, "r1")
        XCTAssertEqual(sut.uiState.reviews[1].id, "r2")

        // canLoadMore still true (cursor preserved so retry is possible)
        XCTAssertTrue(sut.uiState.canLoadMore, "canLoadMore must remain true so retry is possible")

        // isLoadingMore reset
        XCTAssertFalse(sut.uiState.isLoadingMore)
    }

    // MARK: - No connection → offline mode

    /// Verifies that with no connection, reviews are not loaded (offline mode).
    func testNoConnectionReturnsEmptyReviews() async {
        let sut = makeSUT(withConnection: false)
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        XCTAssertTrue(sut.uiState.reviews.isEmpty)
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertNil(sut.uiState.reviewsError)
    }

    // MARK: - Default sort is createdDateDescending

    /// Verifies that the default sort order used by the model is newest-first.
    func testDefaultSortIsCreatedDateDescending() async {
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        XCTAssertEqual(connection.lastFetchReviewsSort, .createdDateDescending)
    }

    // MARK: - T-W20 Gap Coverage: Loading States After Completion

    /// Verifies that BOTH isLoadingRating and isLoading are false after
    /// loadRatingsIfNeeded completes, regardless of success or failure in
    /// either concurrent path.
    func testBothLoadingFlagsFalseAfterCompletion() async {
        // Given: both succeed
        seedLookupResponse(bundleId: "com.flags.test", country: "us", averageRating: 4.0, ratingCount: 100)
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [makeReview()], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.flags.test", accountId: "acct-001")

        XCTAssertFalse(sut.uiState.isLoadingRating, "isLoadingRating must be false after completion")
        XCTAssertFalse(sut.uiState.isLoading, "isLoading must be false after completion")
        XCTAssertFalse(sut.uiState.isLoadingMore, "isLoadingMore must be false after initial load")
    }

    // MARK: - T-W20 Gap Coverage: Error Clearing on Retry (SF-1)

    /// Verifies that `ratingError` transitions from non-nil (after a failed
    /// lookup) back to `nil` (after a successful retry) on the SAME model
    /// instance, mirroring `testReviewsErrorClearedOnRetryStart`.
    func testRatingErrorClearedOnRetry() async {
        // Given: first call fails rating (all storefronts throw)
        lookupNetworking.shouldThrowAll = true
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertEqual(sut.uiState.ratingError, "Rating unavailable", "Precondition: rating error set after failure")
        XCTAssertNil(sut.uiState.aggregateRating, "Precondition: aggregate nil after failure")

        // When: flip the mock to succeed and seed a valid response, then retry
        lookupNetworking.shouldThrowAll = false
        seedLookupResponse(bundleId: "com.example.app", country: "us", averageRating: 4.5, ratingCount: 500)

        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: ratingError is cleared and aggregate is populated
        XCTAssertNil(sut.uiState.ratingError, "ratingError should be nil after successful retry")
        XCTAssertNotNil(sut.uiState.aggregateRating, "aggregate should be populated after successful retry")
        XCTAssertEqual(sut.uiState.aggregateRating?.totalCount, 500)
    }

    /// Verifies that reviewsError is cleared when loadRatingsIfNeeded is called
    /// again (retry scenario), regardless of the outcome.
    func testReviewsErrorClearedOnRetryStart() async {
        // Given: first call fails reviews
        connection.fetchReviewsResultQueue = [
            .failure(NSError(domain: "net", code: -1)),
            .success(ReviewsPage(reviews: [makeReview(id: "retry-ok")], hasNextPage: false, cursor: nil)),
        ]

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertNotNil(sut.uiState.reviewsError, "Precondition: reviewsError set after failure")

        // When: second call (retry)
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: reviewsError is cleared (the second call succeeded)
        XCTAssertNil(sut.uiState.reviewsError, "reviewsError should be cleared after successful retry")
        XCTAssertEqual(sut.uiState.reviews.count, 1)
        XCTAssertEqual(sut.uiState.reviews[0].id, "retry-ok")
    }

    // MARK: - T-W20 Gap Coverage: Sort + Filter with Load More

    /// Verifies that after calling setSort and setFilterRating, a subsequent
    /// loadNextPage passes the updated sort and filter to the connection.
    func testSortAndFilterPassedThroughOnLoadMore() async {
        // Given: page 1 with default sort/filter
        let page1 = [makeReview(id: "r1")]
        let page2 = [makeReview(id: "r2")]
        connection.fetchReviewsResultQueue = [
            .success(ReviewsPage(reviews: page1, hasNextPage: true, cursor: "next")),
            .success(ReviewsPage(reviews: page2, hasNextPage: false, cursor: nil)),
        ]

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Verify default sort on page 1
        XCTAssertEqual(connection.lastFetchReviewsSort, .createdDateDescending)
        XCTAssertNil(connection.lastFetchReviewsFilterRating)

        // When: change sort and filter, then load more
        sut.setSort(.ratingAscending)
        sut.setFilterRating(["5"])
        await sut.loadNextPage(appId: "app-001")

        // Then: Load More used the updated sort and filter
        XCTAssertEqual(connection.lastFetchReviewsSort, .ratingAscending,
                       "Load More should use the updated sort order")
        XCTAssertEqual(connection.lastFetchReviewsFilterRating, ["5"],
                       "Load More should use the updated filter rating")
        XCTAssertEqual(sut.uiState.reviews.count, 2, "Page 2 reviews appended")
    }

    // MARK: - T-W20 Gap Coverage: BundleId Passthrough to Lookup (AC-W10-3)

    /// Verifies that the bundleId passed to loadRatingsIfNeeded is forwarded
    /// to the ITunesLookupService, ensuring aggregate rating reflects the
    /// selected app (AC-W10-3).
    func testBundleIdPassedThroughToLookupService() async {
        // Given: seed responses for a specific bundleId
        let specificBundleId = "com.specific.myapp"
        seedLookupResponse(
            bundleId: specificBundleId,
            country: "us",
            averageRating: 3.7,
            ratingCount: 2500
        )
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: specificBundleId, accountId: "acct-001")

        // Then: the aggregate should contain the data from our specific bundleId
        XCTAssertNotNil(sut.uiState.aggregateRating)
        XCTAssertEqual(sut.uiState.aggregateRating?.totalCount, 2500,
                       "Rating total should match the seeded data for the specific bundleId")

        // Verify the networking layer received URLs with the correct bundleId
        let urls = lookupNetworking.fetchedURLs
        for url in urls {
            XCTAssertTrue(
                url.absoluteString.contains("bundleId=\(specificBundleId)"),
                "Every lookup URL should contain the passed bundleId: \(url.absoluteString)"
            )
        }
    }

    // MARK: - T-W20 Gap Coverage: Load More Appends Correctly (AC-W11-3)

    /// Verifies that multiple Load More calls continue to append reviews
    /// cumulatively (page 1 + page 2 + page 3).
    func testMultipleLoadMoreCallsAppendCumulatively() async {
        let page1 = [makeReview(id: "r1")]
        let page2 = [makeReview(id: "r2")]
        let page3 = [makeReview(id: "r3")]

        connection.fetchReviewsResultQueue = [
            .success(ReviewsPage(reviews: page1, hasNextPage: true, cursor: "c2")),
            .success(ReviewsPage(reviews: page2, hasNextPage: true, cursor: "c3")),
            .success(ReviewsPage(reviews: page3, hasNextPage: false, cursor: nil)),
        ]

        let sut = makeSUT()

        // Page 1
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")
        XCTAssertEqual(sut.uiState.reviews.count, 1)
        XCTAssertTrue(sut.uiState.canLoadMore)

        // Page 2
        await sut.loadNextPage(appId: "app-001")
        XCTAssertEqual(sut.uiState.reviews.count, 2)
        XCTAssertTrue(sut.uiState.canLoadMore)
        XCTAssertEqual(connection.lastFetchReviewsCursor, "c2")

        // Page 3 (final)
        await sut.loadNextPage(appId: "app-001")
        XCTAssertEqual(sut.uiState.reviews.count, 3)
        XCTAssertFalse(sut.uiState.canLoadMore, "Should be false after final page")
        XCTAssertEqual(connection.lastFetchReviewsCursor, "c3")

        // Verify order is preserved: r1, r2, r3
        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["r1", "r2", "r3"])
    }

    // MARK: - T-W20 Gap Coverage: Both Fail Simultaneously (AC-W11-6)

    /// Verifies that when BOTH the rating lookup and reviews fail simultaneously,
    /// both error states are set and loading flags are correctly reset.
    func testBothRatingAndReviewsFailSimultaneously() async {
        // Given: both fail
        lookupNetworking.shouldThrowAll = true
        connection.fetchReviewsResult = .failure(NSError(domain: "net", code: -1))

        let sut = makeSUT()
        await sut.loadRatingsIfNeeded(appId: "app-001", bundleId: "com.example.app", accountId: "acct-001")

        // Then: both errors are set
        XCTAssertNil(sut.uiState.aggregateRating)
        XCTAssertEqual(sut.uiState.ratingError, "Rating unavailable")
        XCTAssertNotNil(sut.uiState.reviewsError)
        XCTAssertEqual(sut.uiState.reviewsError, "Failed to load reviews.")

        // Both loading flags are reset
        XCTAssertFalse(sut.uiState.isLoadingRating)
        XCTAssertFalse(sut.uiState.isLoading)

        // Reviews are empty
        XCTAssertTrue(sut.uiState.reviews.isEmpty)
    }
}
