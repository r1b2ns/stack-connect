import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol RatingsReviewsViewModelProtocol: ObservableObject {
    var uiState: RatingsReviewsUiState { get set }
    /// Loads once per screen: returning from a review keeps the list as it was.
    func loadIfNeeded() async
    /// Loads the first page again (pull to refresh, sort change).
    func load() async
    /// Pull to refresh: same as `load()`, tracked as a `refresh` action.
    func refresh() async
    /// Appends the next page. Also the retry after a failed page.
    func loadMore() async
    func applyFilter(rating: Int?) async
    func reply(to review: CustomerReviewModel, body: String) async
    func cancelReply()
    func deleteResponse(for review: CustomerReviewModel) async
}

// MARK: - UiState

struct RatingsReviewsUiState {
    var appId: String
    var bundleId: String
    var account: AccountModel
    /// What the account's store supports (sort orders, reply deletion, copy).
    var traits: CustomerReviewsTraits
    var reviews: [CustomerReviewModel] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMorePages = false
    /// Last failed next page, shown with a retry where the next page goes.
    var loadMoreError: String?
    var isSending = false
    /// Cached reviews are on screen while the API is being asked for fresh ones.
    var showSyncToast = false
    var toastMessage: ToastMessage?
    var error: String?

    // App Store rating (aggregated from iTunes Lookup across all storefronts)
    var storeAverageRating: Double?
    var storeRatingCount: Int?
    var storefronts: [iTunesStorefrontInfo] = []

    // Filters
    var sortOption: ReviewSortOption = .newest
    var filterRating: Int? = nil

    // Reply sheet
    var replyingTo: CustomerReviewModel?
    var replyText: String = ""
    /// Last reply failure, shown inside the reply composer.
    var replyError: String?

    /// Average rating from the App Store (iTunes Lookup API).
    var averageRating: Double {
        if let store = storeAverageRating { return store }
        return 0
    }

    var ratingCountLabel: String {
        let count = totalRatingCount
        guard count > 0 else { return "" }
        return "\(count.formatted()) \(String(localized: "ratings"))"
    }

    /// Total ratings across every storefront (matches what is shown on the App Store).
    var totalRatingCount: Int {
        storeRatingCount ?? 0
    }

    /// Replying is gated by the account's `review` rules (edit), for every store.
    var canReply: Bool {
        account.canEdit(.review)
    }

    /// Needs the account's `review` delete rule and a store that can delete
    /// replies (Google Play can't).
    var canDeleteReplies: Bool {
        traits.canDeleteReplies && account.canDelete(.review)
    }

    /// The sort menu only appears when the store serves more than one order.
    var showsSortMenu: Bool {
        traits.sortOptions.count > 1
    }

    /// Another page can be asked for (offered as "Load More" when the list
    /// doesn't fill the screen, e.g. a rating filter on Google Play).
    var canLoadMore: Bool {
        hasMorePages && !isLoadingMore
    }
}

enum ReviewSortOption: String, CaseIterable, Identifiable {
    case newest = "-createdDate"
    case oldest = "createdDate"
    case highestRating = "-rating"
    case lowestRating = "rating"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest:        return String(localized: "Newest")
        case .oldest:        return String(localized: "Oldest")
        case .highestRating: return String(localized: "Highest Rating")
        case .lowestRating:  return String(localized: "Lowest Rating")
        }
    }
}

// MARK: - Implementation

/// Ratings & Reviews of one app, for any store behind `CustomerReviewsServicing`
/// (App Store Connect, Google Play).
///
/// Stores with a `cache` (Google Play) are offline-first: the cached first page
/// is shown while the API is asked for a fresh one, and kept when that fails.
///
/// Loads run in tasks this ViewModel owns, not in the caller's: the screen's
/// `.task` is cancelled when a review is pushed, and a cancelled iTunes sweep
/// would leave a partial rating summary behind.
@MainActor
final class RatingsReviewsViewModel: RatingsReviewsViewModelProtocol {

    /// Reviews requested per page.
    static let pageSize = 50

    /// Google Play filters each page by rating on the client, so a filtered page
    /// can come back empty while more pages exist. Up to this many such pages are
    /// skipped per request, so the list (and its load-more trigger) isn't left
    /// empty — bounded because each page counts against Google's hourly quota.
    static let maxEmptyPagesSkipped = 4

    @Published var uiState: RatingsReviewsUiState

    private let service: (any CustomerReviewsServicing)?
    private let cache: (any CustomerReviewsCaching)?
    private let ratingSummaryFetcher: any AppStoreRatingSummaryFetching
    private let analytics: AnalyticsTracking
    private var nextPageToken: String?
    /// The latest load. Non-`nil` once the screen has loaded (or is loading).
    /// Its value says whether the first page loaded.
    private var loadTask: Task<Bool, Never>?
    /// The rating summary on screen came from a sweep of every storefront.
    private var hasCompleteRatingSummary = false
    /// Bumped whenever the list starts over (load, sort, filter): a page asked
    /// for an older list is dropped instead of landing on the new one.
    private var listGeneration = 0

    /// - Parameters:
    ///   - service: the account's reviews backend; `nil` when its credentials are
    ///     missing (the screen then explains it instead of loading).
    ///   - cache: offline cache of the first page, for stores that have one.
    ///   - ratingSummaryFetcher: App Store rating summary, for stores that show
    ///     one (`traits.showsStoreRatingSummary`).
    init(
        appId: String,
        bundleId: String,
        account: AccountModel,
        service: (any CustomerReviewsServicing)?,
        cache: (any CustomerReviewsCaching)? = nil,
        ratingSummaryFetcher: any AppStoreRatingSummaryFetching = BackendEnvironment.ratingSummaryFetcher,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = RatingsReviewsUiState(
            appId: appId,
            bundleId: bundleId,
            account: account,
            traits: service?.traits ?? .appStore
        )
        self.service = service
        self.cache = cache
        self.ratingSummaryFetcher = ratingSummaryFetcher
        self.analytics = analytics
    }

    func loadIfNeeded() async {
        if let loadTask {
            // Already loaded, or still loading: wait for it, never load again.
            _ = await loadTask.value
            return
        }
        await load()
    }

    func load() async {
        _ = await startLoad()
    }

    /// Pull-to-refresh: same load, tracked as a `refresh` action with its outcome.
    func refresh() async {
        let succeeded = await startLoad()
        analytics.track(.action(.refresh, on: .ratingsReviews, result: succeeded ? .success : .failure))
    }

    /// Runs `performLoad` in a task this ViewModel owns (see the type's docs).
    /// Returns `true` when the first page loaded.
    private func startLoad() async -> Bool {
        let task = Task { await self.performLoad() }
        loadTask = task
        return await task.value
    }

    /// Returns `true` when the first page loaded.
    private func performLoad() async -> Bool {
        listGeneration += 1
        let generation = listGeneration
        uiState.error = nil
        uiState.loadMoreError = nil
        uiState.hasMorePages = false
        nextPageToken = nil

        // Per-app scope of an imported account: an app outside it is never loaded.
        guard uiState.account.allowsApp(bundleId: uiState.bundleId) else {
            uiState.reviews = []
            uiState.error = String(localized: "This app isn't included in the apps shared with this account.")
            return false
        }

        // Defense in depth (D16): every entry point checks the `review` view rule
        // before opening this screen; an account without it never loads reviews.
        guard uiState.account.canView(.review) else {
            uiState.reviews = []
            uiState.error = String(localized: "You don't have permission to view ratings and reviews.")
            return false
        }

        // Offline-first: the cached first page (unfiltered, newest first) while
        // the API answers.
        let cached = isShowingDefaultList ? await cache?.cachedReviews() : nil
        guard generation == listGeneration else { return false }
        let isShowingCache = !(cached?.isEmpty ?? true)
        uiState.reviews = cached ?? []
        uiState.showSyncToast = isShowingCache
        uiState.isLoading = true

        let succeeded: Bool
        if uiState.traits.showsStoreRatingSummary {
            // Fetch App Store rating and reviews in parallel
            async let ratingTask: () = fetchAppStoreRating()
            async let reviewsTask: Bool = fetchFirstPage(isShowingCache: isShowingCache, generation: generation)
            let (_, reviewsLoaded) = await (ratingTask, reviewsTask)
            succeeded = reviewsLoaded
        } else {
            succeeded = await fetchFirstPage(isShowingCache: isShowingCache, generation: generation)
        }

        if generation == listGeneration {
            uiState.isLoading = false
        }
        return succeeded
    }

    /// App Store rating across every storefront: `averageRating` is a
    /// count-weighted mean and `ratingCount` the global sum, matching what users
    /// see on the App Store. A cancelled sweep changes nothing, and a partial one
    /// (some storefronts failed) never replaces a complete summary.
    private func fetchAppStoreRating() async {
        guard let summary = await ratingSummaryFetcher.fetchSummary(bundleId: uiState.bundleId) else {
            Log.print.info("[RatingsReviews] Rating summary cancelled; keeping the current one")
            return
        }
        if !summary.isComplete && hasCompleteRatingSummary {
            Log.print.info("[RatingsReviews] Partial rating summary (\(summary.storefronts.count) storefronts); keeping the complete one")
            return
        }

        hasCompleteRatingSummary = summary.isComplete
        uiState.storefronts = summary.storefronts
        uiState.storeAverageRating = summary.averageRating
        uiState.storeRatingCount = summary.ratingCount
        Log.print.info("[RatingsReviews] Rating summary across \(summary.storefronts.count) storefronts: avg \(summary.averageRating ?? 0), count \(summary.ratingCount), complete: \(summary.isComplete)")
    }

    /// Returns `true` when the first page was fetched (and is still current).
    ///
    /// - Parameters:
    ///   - isShowingCache: cached reviews are on screen; an offline failure then
    ///     keeps them without an extra warning (the global offline banner
    ///     already says so).
    ///   - generation: the `listGeneration` this page is for; dropped if the
    ///     list started over meanwhile.
    @discardableResult
    private func fetchFirstPage(isShowingCache: Bool, generation: Int) async -> Bool {
        guard let service else {
            uiState.reviews = []
            uiState.error = String(localized: "No credentials found for this account.")
            Log.print.error("[RatingsReviews] No credentials for account: \(self.uiState.account.name)")
            return false
        }

        do {
            let page = try await fetchPage(after: nil, service: service)
            guard generation == listGeneration else { return false }

            uiState.reviews = page.reviews
            uiState.hasMorePages = page.hasNextPage
            nextPageToken = page.nextPageToken
            if isShowingDefaultList {
                await cache?.saveReviews(page.reviews)
            }

            Log.print.info("[RatingsReviews] Loaded \(page.reviews.count) reviews, hasMore: \(page.hasNextPage), filter: \(self.uiState.filterRating?.description ?? "all")")
            return true
        } catch {
            Log.print.error("[RatingsReviews] Failed to load: \(error.localizedDescription)")
            guard generation == listGeneration else { return false }
            if !(isShowingCache && OfflineError.isConnectivityFailure(error)) {
                uiState.error = service.message(for: error, operation: .load)
            }
            return false
        }
    }

    func applyFilter(rating: Int?) async {
        listGeneration += 1
        let generation = listGeneration
        uiState.filterRating = rating
        uiState.reviews = []
        uiState.error = nil
        uiState.loadMoreError = nil
        uiState.hasMorePages = false
        uiState.isLoading = true
        nextPageToken = nil

        let succeeded = await fetchFirstPage(isShowingCache: false, generation: generation)

        if generation == listGeneration {
            uiState.isLoading = false
        }

        // Only the star filter (1–5) is sent; `nil` means "all ratings".
        var parameters: [String: AnalyticsValue] = [:]
        if let rating { parameters[AnalyticsParameterKey.rating] = .int(rating) }
        analytics.track(.action(.filterReviews, on: .ratingsReviews, result: succeeded ? .success : .failure, parameters: parameters))
    }

    /// Every call asks the store for at most `1 + maxEmptyPagesSkipped` pages,
    /// and the screen only calls it when the next-page row appears, after a page
    /// that added reviews, or on "Load More" — never in a loop on its own, since
    /// Google Play counts every page against an hourly quota.
    func loadMore() async {
        guard uiState.canLoadMore, let token = nextPageToken, let service else { return }
        let generation = listGeneration
        uiState.isLoadingMore = true
        uiState.loadMoreError = nil

        // Owned here like `load()`: the next-page row's `.task` is cancelled as
        // soon as it scrolls away.
        await Task {
            defer { self.uiState.isLoadingMore = false }
            do {
                let page = try await self.fetchPage(after: token, service: service)
                guard generation == self.listGeneration else { return }

                self.uiState.reviews.append(contentsOf: page.reviews)
                self.uiState.hasMorePages = page.hasNextPage
                self.nextPageToken = page.nextPageToken

                Log.print.info("[RatingsReviews] Loaded \(page.reviews.count) more reviews, total: \(self.uiState.reviews.count)")
            } catch {
                Log.print.error("[RatingsReviews] Failed to load more: \(error.localizedDescription)")
                guard generation == self.listGeneration else { return }
                self.uiState.loadMoreError = service.message(for: error, operation: .load)
            }
        }.value
    }

    func reply(to review: CustomerReviewModel, body: String) async {
        analytics.track(.buttonTap(.send, on: .reviewReply))
        guard uiState.canReply else {
            uiState.toastMessage = ToastMessage(
                String(localized: "This account doesn't have permission to reply to reviews."),
                icon: "exclamationmark.triangle.fill"
            )
            return
        }
        guard let service else {
            analytics.track(.action(.replyToReview, on: .reviewReply, result: .failure))
            return
        }

        uiState.isSending = true
        uiState.replyError = nil

        do {
            let response = try await service.reply(toReviewId: review.id, body: body, replacingResponseId: nil)

            if let idx = uiState.reviews.firstIndex(where: { $0.id == review.id }) {
                uiState.reviews[idx].applyResponse(response)
            }

            uiState.replyingTo = nil
            uiState.replyText = ""
            uiState.toastMessage = ToastMessage(String(localized: "Reply sent"), icon: "paperplane.fill")
            Log.print.info("[RatingsReviews] Replied to review \(review.id)")
            await cache?.saveResponse(response, forReviewId: review.id)
            analytics.track(.action(.replyToReview, on: .reviewReply, result: .success))
        } catch {
            analytics.track(.action(.replyToReview, on: .reviewReply, result: .failure))
            let message = service.message(for: error, operation: .reply)
            uiState.replyError = message
            uiState.toastMessage = ToastMessage(message, icon: "exclamationmark.triangle.fill")
            Log.print.error("[RatingsReviews] Reply failed: \(error.localizedDescription)")
        }

        uiState.isSending = false
    }

    /// Closes the composer and drops its draft and error. Also runs when the
    /// sheet is swiped away, so the next reply starts clean.
    func cancelReply() {
        uiState.replyingTo = nil
        uiState.replyText = ""
        uiState.replyError = nil
    }

    func deleteResponse(for review: CustomerReviewModel) async {
        analytics.track(.buttonTap(.delete, on: .ratingsReviews))
        guard uiState.canDeleteReplies, let responseId = review.responseId else { return }
        guard let service else {
            analytics.track(.action(.deleteReviewResponse, on: .ratingsReviews, result: .failure))
            return
        }

        do {
            try await service.deleteReply(responseId: responseId)

            if let idx = uiState.reviews.firstIndex(where: { $0.id == review.id }) {
                uiState.reviews[idx].responseId = nil
                uiState.reviews[idx].responseBody = nil
                uiState.reviews[idx].responseState = nil
                uiState.reviews[idx].responseDate = nil
            }

            uiState.toastMessage = ToastMessage(String(localized: "Reply deleted"), icon: "trash")
            Log.print.info("[RatingsReviews] Deleted response for review \(review.id)")
            analytics.track(.action(.deleteReviewResponse, on: .ratingsReviews, result: .success))
        } catch {
            analytics.track(.action(.deleteReviewResponse, on: .ratingsReviews, result: .failure))
            uiState.toastMessage = ToastMessage(
                service.message(for: error, operation: .deleteReply),
                icon: "exclamationmark.triangle.fill"
            )
            Log.print.error("[RatingsReviews] Delete response failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    /// Only the unfiltered, newest-first list is cached.
    private var isShowingDefaultList: Bool {
        uiState.filterRating == nil && uiState.sortOption == .newest
    }

    /// Fetches the page after `token`, skipping (a bounded number of) empty pages
    /// that still have a successor. See `maxEmptyPagesSkipped`.
    private func fetchPage(
        after token: String?,
        service: any CustomerReviewsServicing
    ) async throws -> CustomerReviewsPageModel {
        var page = try await service.fetchReviewsPage(
            appId: uiState.appId,
            sort: uiState.sortOption,
            filterRating: uiState.filterRating,
            limit: Self.pageSize,
            pageToken: token
        )
        var skipped = 0
        while page.reviews.isEmpty, let next = page.nextPageToken, skipped < Self.maxEmptyPagesSkipped {
            skipped += 1
            page = try await service.fetchReviewsPage(
                appId: uiState.appId,
                sort: uiState.sortOption,
                filterRating: uiState.filterRating,
                limit: Self.pageSize,
                pageToken: next
            )
        }
        return page
    }
}
