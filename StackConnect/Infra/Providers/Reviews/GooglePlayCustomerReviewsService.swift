import Foundation
import StackCoreRust

/// Google Play reviews through `GooglePlayAccountConnection` (Rust core).
///
/// Play specifics (see `CustomerReviewsTraits.googlePlay`): newest first only,
/// replies are upserts (editing just replies again) and cannot be deleted, the
/// review id is an opaque composite passed through unchanged, and Google only
/// shares recent reviews with a comment.
struct GooglePlayCustomerReviewsService: CustomerReviewsServicing {

    let connection: any GooglePlayReviewsConnecting

    var traits: CustomerReviewsTraits { .googlePlay }

    /// `appId` is the package name. `sort` is ignored: Google's own order (newest
    /// first) is the only one, and it is the only option the traits offer.
    func fetchReviewsPage(
        appId: String,
        sort: ReviewSortOption,
        filterRating: Int?,
        limit: Int,
        pageToken: String?
    ) async throws -> CustomerReviewsPageModel {
        try await connection.fetchCustomerReviewsPage(
            packageName: appId,
            filterRating: filterRating,
            limit: limit,
            pageToken: pageToken
        )
    }

    /// Replying again replaces the previous reply, so `replacingResponseId` needs
    /// no extra call.
    func reply(
        toReviewId reviewId: String,
        body: String,
        replacingResponseId: String?
    ) async throws -> CustomerReviewResponseModel {
        let response = try await connection.replyToReview(reviewId: reviewId, body: body)
        // Play replies are public right away and carry no state.
        return CustomerReviewResponseModel(
            id: response.id,
            body: response.body ?? body,
            state: response.state,
            date: response.date ?? Date()
        )
    }

    /// The screens never offer it (`canDeleteReplies == false`); fails the same
    /// way the core does.
    func deleteReply(responseId: String) async throws {
        throw StackError.Unsupported(message: "Google Play has no API to delete a review reply.")
    }

    /// A reply has its own copy for Google's 400 (too long) and 404 (review no
    /// longer shared); listing keeps the package copy for a 404.
    func message(for error: Error, operation: CustomerReviewsOperation) -> String {
        GooglePlayErrorTranslator.friendlyMessage(
            for: error,
            operation: operation == .reply ? .replyToReview : .general
        )
    }
}

/// `CustomerReviewsCaching` for one Google Play app of one account, stored as a
/// `GooglePlayReviewsCache` entry (removed by `AccountCascadeDeleter`).
struct GooglePlayCustomerReviewsCache: CustomerReviewsCaching {

    let store: GooglePlayAppCacheStore<GooglePlayReviewsCache>

    init(storage: PersistentStorable, accountId: String, packageName: String) {
        self.store = GooglePlayAppCacheStore(storage: storage, accountId: accountId, packageName: packageName)
    }

    func cachedReviews() async -> [CustomerReviewModel]? {
        await store.load()?.reviews
    }

    func saveReviews(_ reviews: [CustomerReviewModel]) async {
        await store.save(GooglePlayReviewsCache(
            accountId: store.accountId,
            packageName: store.packageName,
            reviews: reviews
        ))
    }
}
