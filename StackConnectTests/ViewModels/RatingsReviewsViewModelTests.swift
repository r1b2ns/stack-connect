import XCTest
import StackCoreRust
@testable import StackConnect

private let testPackageName = "com.example.app"

/// Ratings & Reviews on the reviews provider seam. Google Play runs through the
/// real `GooglePlayCustomerReviewsService` + `GooglePlayCustomerReviewsCache`
/// over in-memory mocks; App Store behaviour through `MockCustomerReviewsService`.
@MainActor
final class RatingsReviewsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var connection: MockGooglePlayAccountConnection!
    private var ratingFetcher: MockAppStoreRatingSummaryFetcher!

    private let packageName = testPackageName
    private let playAccount = AccountModel(name: "Play Team", providerType: .googlePlay)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        connection = MockGooglePlayAccountConnection()
        ratingFetcher = MockAppStoreRatingSummaryFetcher()
    }

    override func tearDown() async throws {
        storage = nil
        connection = nil
        ratingFetcher = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makePlaySUT(account: AccountModel? = nil, withService: Bool = true) -> RatingsReviewsViewModel {
        let account = account ?? playAccount
        return RatingsReviewsViewModel(
            appId: packageName,
            bundleId: packageName,
            account: account,
            service: withService ? GooglePlayCustomerReviewsService(connection: connection) : nil,
            cache: GooglePlayCustomerReviewsCache(storage: storage, accountId: account.id, packageName: packageName),
            ratingSummaryFetcher: ratingFetcher
        )
    }

    /// App Store traits without the iTunes Lookup summary, so no test hits the network.
    private func appStoreService() -> MockCustomerReviewsService {
        var traits = CustomerReviewsTraits.appStore
        traits.showsStoreRatingSummary = false
        return MockCustomerReviewsService(traits: traits)
    }

    private func makeAppleSUT(service: MockCustomerReviewsService, account: AccountModel? = nil) -> RatingsReviewsViewModel {
        RatingsReviewsViewModel(
            appId: "123",
            bundleId: "com.example.ios",
            account: account ?? AccountModel(name: "Team", providerType: .apple),
            service: service,
            cache: nil,
            ratingSummaryFetcher: ratingFetcher
        )
    }

    private func seedCache(_ reviews: [CustomerReviewModel]) async {
        await GooglePlayCustomerReviewsCache(storage: storage, accountId: playAccount.id, packageName: packageName)
            .saveReviews(reviews)
    }

    private func cachedReviewIds() async -> [String]? {
        await GooglePlayCustomerReviewsCache(storage: storage, accountId: playAccount.id, packageName: packageName)
            .cachedReviews()?.map(\.id)
    }

    private func importedPlayAccount(review: [AccountPermission], appsBundles: [String]? = nil) -> AccountModel {
        AccountModel(
            name: "Imported",
            providerType: .googlePlay,
            rules: AccountRules(apps: AccountPermission.allCases, review: review),
            origin: .imported,
            appsBundles: appsBundles
        )
    }

    // MARK: - Google Play traits

    func testPlayHidesTheSortMenuAndReplyDeletion() {
        let sut = makePlaySUT()

        XCTAssertEqual(sut.uiState.traits, .googlePlay)
        XCTAssertFalse(sut.uiState.showsSortMenu)
        XCTAssertTrue(sut.uiState.canReply)
        XCTAssertFalse(sut.uiState.canDeleteReplies, "Google Play has no reply deletion, whatever the rules")
    }

    func testInitDoesNotLoad() async {
        _ = makePlaySUT()
        await Task.yield()

        XCTAssertTrue(connection.reviewsPageRequests.isEmpty)
    }

    func testLoadIfNeededLoadsOnlyOnce() async {
        let sut = makePlaySUT()

        await sut.loadIfNeeded()
        await sut.loadIfNeeded()

        XCTAssertEqual(connection.reviewsPageRequests.count, 1, "Returning from a review keeps the list")
    }

    // MARK: - Offline-first (Google Play)

    func testLoadShowsCachedReviewsThenTheFreshFirstPageAndCachesIt() async {
        await seedCache([makeReview("cached")])
        let sut = makePlaySUT()
        connection.fetchReviewsPageHandler = { _ in
            let (ids, toast) = await MainActor.run { (sut.uiState.reviews.map(\.id), sut.uiState.showSyncToast) }
            XCTAssertEqual(ids, ["com.example.app/cached"])
            XCTAssertTrue(toast)
            return makePage([makeReview("fresh")], next: "t2")
        }

        await sut.load()

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/fresh"])
        XCTAssertTrue(sut.uiState.hasMorePages)
        XCTAssertNil(sut.uiState.error)
        XCTAssertFalse(sut.uiState.isLoading)
        XCTAssertEqual(connection.reviewsPageRequests, [
            .init(packageName: packageName, filterRating: nil, limit: RatingsReviewsViewModel.pageSize, pageToken: nil)
        ])
        let cached = await cachedReviewIds()
        XCTAssertEqual(cached, ["com.example.app/fresh"])
    }

    func testFailedSyncKeepsTheCachedReviewsWithAnInlineError() async {
        await seedCache([makeReview("cached")])
        connection.fetchReviewsPageHandler = { _ in throw StackError.Http(status: 503, message: "") }
        let sut = makePlaySUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/cached"])
        XCTAssertEqual(sut.uiState.error, String(localized: "Google Play is temporarily unavailable. Try again in a few minutes."))
        let cached = await cachedReviewIds()
        XCTAssertEqual(cached, ["com.example.app/cached"])
    }

    func testOfflineWithCachedReviewsKeepsThemSilently() async {
        await seedCache([makeReview("cached")])
        connection.fetchReviewsPageHandler = { _ in throw OfflineError.noConnection }
        let sut = makePlaySUT()

        await sut.load()

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/cached"])
        XCTAssertNil(sut.uiState.error)
    }

    func testOfflineWithoutCacheShowsTheOfflineError() async {
        connection.fetchReviewsPageHandler = { _ in throw OfflineError.noConnection }
        let sut = makePlaySUT()

        await sut.load()

        XCTAssertTrue(sut.uiState.reviews.isEmpty)
        XCTAssertEqual(sut.uiState.error, OfflineError.noConnection.localizedDescription)
    }

    func testMissingCredentialsExplainsInsteadOfLoading() async {
        let sut = makePlaySUT(withService: false)

        await sut.load()

        XCTAssertEqual(sut.uiState.error, String(localized: "No credentials found for this account."))
        XCTAssertTrue(connection.reviewsPageRequests.isEmpty)
    }

    func testAppOutsideTheImportedScopeIsNeverLoaded() async {
        let sut = makePlaySUT(account: importedPlayAccount(review: [.view], appsBundles: ["com.other.app"]))

        await sut.load()

        XCTAssertEqual(sut.uiState.error, String(localized: "This app isn't included in the apps shared with this account."))
        XCTAssertTrue(connection.reviewsPageRequests.isEmpty)
    }

    // MARK: - Paging and filtering

    func testLoadMorePassesTheOpaqueTokenBackAndAppends() async {
        connection.fetchReviewsPageHandler = { request in
            request.pageToken == nil
                ? makePage([makeReview("r1")], next: "opaque==")
                : makePage([makeReview("r2")])
        }
        let sut = makePlaySUT()

        await sut.load()
        await sut.loadMore()

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/r1", "com.example.app/r2"])
        XCTAssertFalse(sut.uiState.hasMorePages)
        XCTAssertEqual(connection.reviewsPageRequests.map(\.pageToken), [nil, "opaque=="])
    }

    /// Google filters by rating per page on the client: an empty page with a
    /// successor is skipped instead of showing "No Reviews".
    func testEmptyFilteredPagesAreSkipped() async {
        connection.fetchReviewsPageHandler = { request in
            switch request.pageToken {
            case nil:  return makePage([], next: "p2")
            case "p2": return makePage([makeReview("one-star", rating: 1)], next: "p3")
            default:   return makePage([])
            }
        }
        let sut = makePlaySUT()

        await sut.applyFilter(rating: 1)

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/one-star"])
        XCTAssertTrue(sut.uiState.hasMorePages)
        XCTAssertEqual(connection.reviewsPageRequests.map(\.filterRating), [1, 1])
        XCTAssertEqual(connection.reviewsPageRequests.map(\.pageToken), [nil, "p2"])
    }

    func testSkippingEmptyPagesIsBounded() async {
        connection.fetchReviewsPageHandler = { request in
            makePage([], next: "next-\(request.pageToken ?? "0")")
        }
        let sut = makePlaySUT()

        await sut.applyFilter(rating: 2)

        XCTAssertTrue(sut.uiState.reviews.isEmpty)
        XCTAssertEqual(connection.reviewsPageRequests.count, 1 + RatingsReviewsViewModel.maxEmptyPagesSkipped)
    }

    func testFilteredResultsNeverReplaceTheCache() async {
        await seedCache([makeReview("cached")])
        connection.fetchReviewsPageHandler = { _ in makePage([makeReview("five", rating: 5)]) }
        let sut = makePlaySUT()

        await sut.applyFilter(rating: 5)

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/five"])
        let cached = await cachedReviewIds()
        XCTAssertEqual(cached, ["com.example.app/cached"], "Only the unfiltered first page is cached")
    }

    // MARK: - Replies (Google Play)

    func testReplyPassesTheOpaqueIdAndShowsTheReply() async {
        connection.fetchReviewsPageHandler = { _ in makePage([makeReview("r1")]) }
        let sut = makePlaySUT()
        await sut.load()
        let target = sut.uiState.reviews[0]
        sut.uiState.replyingTo = target
        sut.uiState.replyText = "Thanks!"

        await sut.reply(to: target, body: "Thanks!")

        XCTAssertEqual(connection.replies.map(\.reviewId), ["com.example.app/r1"])
        XCTAssertEqual(sut.uiState.reviews[0].responseBody, "Thanks!")
        XCTAssertEqual(sut.uiState.reviews[0].responseId, "com.example.app/r1")
        XCTAssertNil(sut.uiState.reviews[0].responseState, "Play replies have no moderation state")
        XCTAssertNil(sut.uiState.replyingTo, "The composer closes")
        XCTAssertNil(sut.uiState.replyError)
        XCTAssertEqual(sut.uiState.toastMessage?.text, String(localized: "Reply sent"))
    }

    func testReplyIsGatedByTheReviewEditRule() async {
        let viewOnly = importedPlayAccount(review: [.view])
        connection.fetchReviewsPageHandler = { _ in makePage([makeReview("r1")]) }
        let sut = makePlaySUT(account: viewOnly)
        await sut.load()

        XCTAssertFalse(sut.uiState.canReply)
        await sut.reply(to: sut.uiState.reviews[0], body: "Thanks!")

        XCTAssertTrue(connection.replies.isEmpty, "No reply without the review edit rule")
        XCTAssertNil(sut.uiState.reviews[0].responseBody)
        XCTAssertEqual(
            sut.uiState.toastMessage?.text,
            String(localized: "This account doesn't have permission to reply to reviews.")
        )
    }

    func testReplyAllowedWithTheReviewEditRule() async {
        let editor = importedPlayAccount(review: [.view, .edit])
        connection.fetchReviewsPageHandler = { _ in makePage([makeReview("r1")]) }
        let sut = makePlaySUT(account: editor)
        await sut.load()

        await sut.reply(to: sut.uiState.reviews[0], body: "Thanks!")

        XCTAssertEqual(connection.replies.count, 1)
        XCTAssertFalse(sut.uiState.canDeleteReplies)
    }

    func testRejectedReplyKeepsTheComposerOpenWithGooglesReason() async {
        connection.fetchReviewsPageHandler = { _ in makePage([makeReview("r1")]) }
        connection.replyHandler = { _, _ in throw StackError.Http(status: 400, message: "Reply too long") }
        let sut = makePlaySUT()
        await sut.load()
        let target = sut.uiState.reviews[0]
        sut.uiState.replyingTo = target
        let longReply = String(repeating: "a", count: 400)
        sut.uiState.replyText = longReply

        await sut.reply(to: target, body: longReply)

        let expected = String(localized: "Google Play rejected this reply. Replies are limited to about \(GooglePlayReviewLimits.replyCharacterLimit) characters — shorten it and try again.")
        XCTAssertEqual(sut.uiState.replyError, expected)
        XCTAssertEqual(sut.uiState.replyingTo?.id, target.id, "The composer stays open")
        XCTAssertEqual(sut.uiState.replyText, longReply, "The draft is kept")
        XCTAssertFalse(sut.uiState.isSending)

        sut.cancelReply()
        XCTAssertNil(sut.uiState.replyError)
        XCTAssertNil(sut.uiState.replyingTo)
    }

    func testDeleteReplyIsANoOpOnGooglePlay() async {
        connection.fetchReviewsPageHandler = { _ in makePage([makeReview("r1", reply: "Thanks")]) }
        let sut = makePlaySUT()
        await sut.load()

        await sut.deleteResponse(for: sut.uiState.reviews[0])

        XCTAssertEqual(sut.uiState.reviews[0].responseBody, "Thanks")
        XCTAssertNil(sut.uiState.toastMessage)
    }

    // MARK: - App Store behaviour through the seam

    func testAppStorePassesTheChosenSortAndUsesNoCache() async {
        let service = appStoreService()
        let sut = makeAppleSUT(service: service)
        XCTAssertTrue(sut.uiState.showsSortMenu)

        sut.uiState.sortOption = .lowestRating
        await sut.load()

        XCTAssertEqual(service.pageRequests, [.init(appId: "123", sort: .lowestRating, filterRating: nil, pageToken: nil)])
        XCTAssertFalse(sut.uiState.showSyncToast)
    }

    func testAppStoreLoadErrorUsesTheServiceCopy() async {
        let service = appStoreService()
        service.pageHandler = { _ in throw URLError(.timedOut) }
        let sut = makeAppleSUT(service: service)

        await sut.load()

        XCTAssertEqual(sut.uiState.error, MockCustomerReviewsService.message(for: .load))
    }

    func testAppStoreDeleteReplyNeedsTheDeleteRule() async {
        let service = appStoreService()
        service.pageHandler = { _ in
            CustomerReviewsPageModel(
                reviews: [CustomerReviewModel(id: "asc-1", rating: 3, responseId: "resp-1", responseBody: "Thanks")],
                nextPageToken: nil
            )
        }
        let editor = AccountModel(
            name: "Imported",
            providerType: .apple,
            rules: AccountRules(review: [.view, .edit]),
            origin: .imported
        )
        let restricted = makeAppleSUT(service: service, account: editor)
        await restricted.load()
        await restricted.deleteResponse(for: restricted.uiState.reviews[0])
        XCTAssertTrue(service.deletedResponseIds.isEmpty)

        let full = makeAppleSUT(service: service)
        await full.load()
        await full.deleteResponse(for: full.uiState.reviews[0])
        XCTAssertEqual(service.deletedResponseIds, ["resp-1"])
        XCTAssertNil(full.uiState.reviews[0].responseBody)
    }

    func testAppStoreReplyShowsTheReturnedResponse() async {
        let service = appStoreService()
        service.pageHandler = { _ in
            CustomerReviewsPageModel(reviews: [CustomerReviewModel(id: "asc-1", rating: 3)], nextPageToken: nil)
        }
        let sut = makeAppleSUT(service: service)
        await sut.load()

        await sut.reply(to: sut.uiState.reviews[0], body: "Hello")

        XCTAssertEqual(service.replyRequests, [.init(reviewId: "asc-1", body: "Hello", replacingResponseId: nil)])
        XCTAssertEqual(sut.uiState.reviews[0].responseId, "resp-asc-1")
        XCTAssertEqual(sut.uiState.reviews[0].responseState, "PENDING_PUBLISH")
    }

    // MARK: - App Store rating summary (S1)

    func testAppStoreRatingSummaryComesFromTheFetcher() async {
        ratingFetcher.handler = { _ in MockAppStoreRatingSummaryFetcher.summary([("br", 5.0, 100), ("us", 4.0, 300)]) }
        let sut = makeAppleSUT(service: MockCustomerReviewsService())

        await sut.load()

        XCTAssertEqual(ratingFetcher.requests, ["com.example.ios"])
        XCTAssertEqual(sut.uiState.storeAverageRating ?? 0, 4.25, accuracy: 0.0001)
        XCTAssertEqual(sut.uiState.storeRatingCount, 400)
        XCTAssertEqual(sut.uiState.storefronts.map(\.country), ["br", "us"])
        XCTAssertFalse(sut.uiState.ratingCountLabel.isEmpty)
    }

    func testCancelledOrPartialSweepNeverOverwritesACompleteSummary() async {
        ratingFetcher.handler = { _ in MockAppStoreRatingSummaryFetcher.summary([("us", 4.5, 1_000)]) }
        let sut = makeAppleSUT(service: MockCustomerReviewsService())
        await sut.load()

        ratingFetcher.handler = { _ in nil }   // cancelled sweep
        await sut.load()
        XCTAssertEqual(sut.uiState.storeAverageRating, 4.5)
        XCTAssertEqual(sut.uiState.storeRatingCount, 1_000)

        ratingFetcher.handler = { _ in MockAppStoreRatingSummaryFetcher.summary([("us", 1.0, 3)], isComplete: false) }
        await sut.load()
        XCTAssertEqual(sut.uiState.storeAverageRating, 4.5, "A partial sweep undercounts")
        XCTAssertEqual(sut.uiState.storeRatingCount, 1_000)
        XCTAssertEqual(sut.uiState.storefronts.map(\.country), ["us"])
    }

    func testPartialSummaryIsShownWhenThereIsNoCompleteOne() async {
        ratingFetcher.handler = { _ in MockAppStoreRatingSummaryFetcher.summary([("us", 3.0, 10)], isComplete: false) }
        let sut = makeAppleSUT(service: MockCustomerReviewsService())

        await sut.load()

        XCTAssertEqual(sut.uiState.storeAverageRating, 3.0)
        XCTAssertEqual(sut.uiState.storeRatingCount, 10)
    }

    /// Opening a review cancels the screen's `.task`; the load (and its
    /// storefront sweep) keeps running in the ViewModel's own task.
    func testOpeningAReviewDoesNotCancelTheLoad() async {
        let gate = AsyncGate()
        let sweepWasCancelled = LockedFlag()
        ratingFetcher.handler = { _ in
            await gate.wait()
            sweepWasCancelled.set(Task.isCancelled)
            return Task.isCancelled ? nil : MockAppStoreRatingSummaryFetcher.summary([("us", 4.0, 50)])
        }
        let service = MockCustomerReviewsService()
        let sut = makeAppleSUT(service: service)

        let screenTask = Task { await sut.loadIfNeeded() }
        await gate.waitForArrivals()
        screenTask.cancel()
        await gate.open()
        await screenTask.value

        XCTAssertFalse(sweepWasCancelled.value)
        XCTAssertEqual(sut.uiState.storeAverageRating, 4.0)
        XCTAssertEqual(sut.uiState.storeRatingCount, 50)

        // Back from the review: nothing reloads.
        await sut.loadIfNeeded()
        XCTAssertEqual(ratingFetcher.requests.count, 1)
        XCTAssertEqual(service.pageRequests.count, 1)
    }

    func testPlayHasNoRatingSummary() async {
        let sut = makePlaySUT()

        await sut.load()

        XCTAssertTrue(ratingFetcher.requests.isEmpty)
        XCTAssertNil(sut.uiState.storeAverageRating)
    }

    // MARK: - View rule (S6)

    func testAccountWithoutTheReviewViewRuleNeverLoads() async {
        let sut = makePlaySUT(account: importedPlayAccount(review: []))

        await sut.load()

        XCTAssertEqual(sut.uiState.error, String(localized: "You don't have permission to view ratings and reviews."))
        XCTAssertTrue(sut.uiState.reviews.isEmpty)
        XCTAssertTrue(connection.reviewsPageRequests.isEmpty)
    }

    func testAppStoreAccountWithoutTheReviewViewRuleNeverLoads() async {
        let service = MockCustomerReviewsService()
        let noReviews = AccountModel(name: "Imported", providerType: .apple, rules: AccountRules(apps: [.view]), origin: .imported)
        let sut = makeAppleSUT(service: service, account: noReviews)

        await sut.load()

        XCTAssertEqual(sut.uiState.error, String(localized: "You don't have permission to view ratings and reviews."))
        XCTAssertTrue(service.pageRequests.isEmpty)
        XCTAssertTrue(ratingFetcher.requests.isEmpty)
    }

    func testReviewViewRuleAloneIsEnoughToLoad() async {
        let sut = makePlaySUT(account: importedPlayAccount(review: [.view]))

        await sut.load()

        XCTAssertNil(sut.uiState.error)
        XCTAssertEqual(connection.reviewsPageRequests.count, 1)
    }

    // MARK: - Next page (S2)

    func testFailedNextPageOffersARetryThatAppends() async {
        let failNextPage = LockedFlag()
        failNextPage.set(true)
        connection.fetchReviewsPageHandler = { request in
            if request.pageToken == nil { return makePage([makeReview("r1")], next: "p2") }
            if failNextPage.value { throw StackError.Http(status: 503, message: "") }
            return makePage([makeReview("r2")])
        }
        let sut = makePlaySUT()
        await sut.load()

        await sut.loadMore()

        XCTAssertEqual(sut.uiState.loadMoreError, String(localized: "Google Play is temporarily unavailable. Try again in a few minutes."))
        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/r1"])
        XCTAssertTrue(sut.uiState.canLoadMore, "The retry stays available")
        XCTAssertNil(sut.uiState.error, "The list itself is fine")

        failNextPage.set(false)
        await sut.loadMore()

        XCTAssertNil(sut.uiState.loadMoreError)
        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/r1", "com.example.app/r2"])
        XCTAssertFalse(sut.uiState.hasMorePages)
        XCTAssertEqual(connection.reviewsPageRequests.map(\.pageToken), [nil, "p2", "p2"])
    }

    /// A rating filter on Google Play can leave the list empty while pages
    /// remain: the screen offers "Load More" instead of "No reviews".
    func testEmptyFilteredListWithMorePagesCanLoadMore() async {
        // Five pages without a 1-star review (more than one call skips), then one.
        connection.fetchReviewsPageHandler = { request in
            let index = Int(request.pageToken ?? "0") ?? 0
            return index < 5 ? makePage([], next: "\(index + 1)") : makePage([makeReview("one-star", rating: 1)])
        }
        let sut = makePlaySUT()

        await sut.applyFilter(rating: 1)

        XCTAssertTrue(sut.uiState.reviews.isEmpty)
        XCTAssertTrue(sut.uiState.hasMorePages)
        XCTAssertTrue(sut.uiState.canLoadMore)

        await sut.loadMore()

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/one-star"])
        XCTAssertFalse(sut.uiState.hasMorePages)
        XCTAssertLessThanOrEqual(
            connection.reviewsPageRequests.count,
            2 * (1 + RatingsReviewsViewModel.maxEmptyPagesSkipped),
            "Each call stays bounded"
        )
    }

    func testNextPageIsAskedOnceWhileInFlight() async {
        let gate = AsyncGate()
        connection.fetchReviewsPageHandler = { request in
            if request.pageToken == nil { return makePage([makeReview("r1")], next: "p2") }
            await gate.wait()
            return makePage([makeReview("r2")])
        }
        let sut = makePlaySUT()
        await sut.load()

        let first = Task { await sut.loadMore() }
        await gate.waitForArrivals()
        XCTAssertFalse(sut.uiState.canLoadMore)
        await sut.loadMore()
        await gate.open()
        await first.value

        XCTAssertEqual(connection.reviewsPageRequests.map(\.pageToken), [nil, "p2"])
        XCTAssertEqual(sut.uiState.reviews.count, 2)
    }

    /// A refresh while the next page is in flight: that page belongs to the old
    /// list and is dropped.
    func testRefreshDropsAPageMeantForTheOldList() async {
        let gate = AsyncGate()
        let refreshed = LockedFlag()
        connection.fetchReviewsPageHandler = { request in
            if request.pageToken == "old-p2" {
                await gate.wait()
                return makePage([makeReview("old-2")], next: "old-p3")
            }
            return refreshed.value
                ? makePage([makeReview("new-1")], next: "new-p2")
                : makePage([makeReview("old-1")], next: "old-p2")
        }
        let sut = makePlaySUT()
        await sut.load()

        let nextPage = Task { await sut.loadMore() }
        await gate.waitForArrivals()
        refreshed.set(true)
        await sut.load()
        await gate.open()
        await nextPage.value

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["com.example.app/new-1"])
        XCTAssertTrue(sut.uiState.hasMorePages)
        XCTAssertFalse(sut.uiState.isLoadingMore)

        await sut.loadMore()
        XCTAssertEqual(connection.reviewsPageRequests.last?.pageToken, "new-p2", "Paging continues from the new list")
    }

    /// Changing the sort while the previous order is still loading: only the
    /// latest order lands on screen.
    func testSortChangeDropsTheOlderLoad() async {
        let gate = AsyncGate()
        let service = appStoreService()
        service.pageHandler = { request in
            if request.sort == .newest {
                await gate.wait()
                return CustomerReviewsPageModel(reviews: [CustomerReviewModel(id: "newest", rating: 5)], nextPageToken: nil)
            }
            return CustomerReviewsPageModel(reviews: [CustomerReviewModel(id: "lowest", rating: 1)], nextPageToken: "t")
        }
        let sut = makeAppleSUT(service: service)

        let firstLoad = Task { await sut.loadIfNeeded() }
        await gate.waitForArrivals()
        sut.uiState.sortOption = .lowestRating
        await sut.load()
        await gate.open()
        await firstLoad.value

        XCTAssertEqual(sut.uiState.reviews.map(\.id), ["lowest"])
        XCTAssertTrue(sut.uiState.hasMorePages)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - Reply keeps the cache in step (N5) and the composer clean (N2)

    func testReplyAlsoUpdatesTheCachedReview() async {
        connection.fetchReviewsPageHandler = { _ in makePage([makeReview("r1"), makeReview("r2")]) }
        let sut = makePlaySUT()
        await sut.load()

        await sut.reply(to: sut.uiState.reviews[1], body: "Thanks!")

        let cached = await GooglePlayCustomerReviewsCache(storage: storage, accountId: playAccount.id, packageName: packageName).cachedReviews()
        XCTAssertEqual(cached?.map(\.id), ["com.example.app/r1", "com.example.app/r2"])
        XCTAssertNil(cached?[0].responseBody)
        XCTAssertEqual(cached?[1].responseBody, "Thanks!")
        XCTAssertEqual(cached?[1].responseId, "com.example.app/r2")
    }

    func testReplyToAReviewOutsideTheCacheLeavesTheCacheAlone() async {
        await seedCache([makeReview("cached")])
        connection.fetchReviewsPageHandler = { _ in makePage([makeReview("five", rating: 5)]) }
        let sut = makePlaySUT()
        await sut.applyFilter(rating: 5)

        await sut.reply(to: sut.uiState.reviews[0], body: "Thanks!")

        let cached = await GooglePlayCustomerReviewsCache(storage: storage, accountId: playAccount.id, packageName: packageName).cachedReviews()
        XCTAssertEqual(cached?.map(\.id), ["com.example.app/cached"])
        XCTAssertNil(cached?[0].responseBody)
    }

    /// Also what swiping the composer away does.
    func testCancelReplyDropsTheDraftAndError() {
        let sut = makePlaySUT()
        sut.uiState.replyingTo = makeReview("r1")
        sut.uiState.replyText = "Half-written"
        sut.uiState.replyError = "Earlier failure"

        sut.cancelReply()

        XCTAssertNil(sut.uiState.replyingTo)
        XCTAssertEqual(sut.uiState.replyText, "")
        XCTAssertNil(sut.uiState.replyError)
    }
}

// MARK: - Fixtures

/// File-scope (nonisolated) so the `@Sendable` mock handlers can build them too.
private func makeReview(_ id: String, rating: Int = 5, reply: String? = nil) -> CustomerReviewModel {
    CustomerReviewModel(
        id: "\(testPackageName)/\(id)",
        rating: rating,
        body: "Body \(id)",
        responseId: reply == nil ? nil : "\(testPackageName)/\(id)",
        responseBody: reply
    )
}

private func makePage(_ reviews: [CustomerReviewModel], next: String? = nil) -> CustomerReviewsPageModel {
    CustomerReviewsPageModel(reviews: reviews, nextPageToken: next)
}
