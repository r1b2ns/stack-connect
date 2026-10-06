import Foundation

/// Provider-agnostic access to one account's customer reviews.
///
/// The Ratings & Reviews list and the Review Detail screens talk only to this
/// seam, so the same screens (and the per-account reply templates) serve App
/// Store Connect and Google Play. Each store states what it can do through
/// `traits`; the screens hide what a store doesn't support.
protocol CustomerReviewsServicing: Sendable {

    var traits: CustomerReviewsTraits { get }

    /// One page of reviews. `pageToken` is `nil` for the first page, otherwise a
    /// previous page's `nextPageToken`, passed back unchanged. A page may be
    /// empty while `nextPageToken` is still set (Google Play filters each page
    /// by rating on the client).
    func fetchReviewsPage(
        appId: String,
        sort: ReviewSortOption,
        filterRating: Int?,
        limit: Int,
        pageToken: String?
    ) async throws -> CustomerReviewsPageModel

    /// Creates the developer reply, or replaces `replacingResponseId` when
    /// editing. Returns the reply the store kept. Review ids are opaque: pass
    /// them back exactly as fetched.
    func reply(
        toReviewId reviewId: String,
        body: String,
        replacingResponseId: String?
    ) async throws -> CustomerReviewResponseModel

    /// Only called when `traits.canDeleteReplies` is true.
    func deleteReply(responseId: String) async throws

    /// User-facing copy for a failed call, in the store's own terms.
    func message(for error: Error, operation: CustomerReviewsOperation) -> String
}

/// What a failed reviews call was doing.
enum CustomerReviewsOperation {
    case load
    case reply
    case deleteReply
}

/// What a store supports, and the copy that names it.
struct CustomerReviewsTraits: Equatable, Sendable {
    /// Orders the store can serve; the sort menu is hidden with only one.
    var sortOptions: [ReviewSortOption]
    var canDeleteReplies: Bool
    /// Whether the App Store rating summary (iTunes Lookup) applies.
    var showsStoreRatingSummary: Bool
    /// Soft limit shown as a counter in the reply composer, if the store has one.
    var replyCharacterLimit: Int?
    /// Composer footer: who will see the reply.
    var replyVisibilityNote: String
    /// Footer of the "Write a Reply" section on the review detail.
    var composeReplyNote: String
    /// Extra note shown with the review list (e.g. which reviews the store shares).
    var listNote: String?

    static var appStore: CustomerReviewsTraits {
        CustomerReviewsTraits(
            sortOptions: ReviewSortOption.allCases,
            canDeleteReplies: true,
            showsStoreRatingSummary: true,
            replyCharacterLimit: nil,
            replyVisibilityNote: String(localized: "Your reply will be visible to all users on the App Store."),
            composeReplyNote: String(localized: "Reply to this review. Your response will be visible on the App Store."),
            listNote: nil
        )
    }

    /// Google Play: newest first only, no reply deletion (a reply can be
    /// replaced), no rating summary, ~350-character replies, and only recent
    /// reviews with a comment (Google's review API limits).
    static var googlePlay: CustomerReviewsTraits {
        CustomerReviewsTraits(
            sortOptions: [.newest],
            canDeleteReplies: false,
            showsStoreRatingSummary: false,
            replyCharacterLimit: GooglePlayReviewLimits.replyCharacterLimit,
            replyVisibilityNote: String(localized: "Your reply will be visible to all users on Google Play."),
            composeReplyNote: String(localized: "Reply to this review. Your response will be visible on Google Play."),
            listNote: String(localized: "Google Play only shares reviews with a comment that were written or edited in the last 7 days. Older reviews are available in Play Console.")
        )
    }
}

/// Offline cache of an app's first page of reviews (unfiltered, newest first).
protocol CustomerReviewsCaching: Sendable {
    func cachedReviews() async -> [CustomerReviewModel]?
    func saveReviews(_ reviews: [CustomerReviewModel]) async
}

extension CustomerReviewsCaching {

    /// Records a reply the store accepted on the cached review, if that review
    /// is cached, so the offline list doesn't show it unanswered until the next
    /// sync. Does nothing for a review outside the cached page.
    func saveResponse(_ response: CustomerReviewResponseModel, forReviewId reviewId: String) async {
        guard var reviews = await cachedReviews(),
              let index = reviews.firstIndex(where: { $0.id == reviewId }) else {
            return
        }
        reviews[index].applyResponse(response)
        await saveReviews(reviews)
    }
}
