import Foundation

/// One page of customer reviews from any store, plus the opaque token that
/// fetches the next one (`nil` on the last page). Pass the token back unchanged.
struct CustomerReviewsPageModel: Hashable {
    var reviews: [CustomerReviewModel]
    var nextPageToken: String?

    var hasNextPage: Bool {
        nextPageToken != nil
    }
}

/// The developer reply a store kept after a reply call.
///
/// App Store Connect returns a new response id and a review state (e.g.
/// `PENDING_PUBLISH`); Google Play reuses the review id and has no state.
struct CustomerReviewResponseModel: Hashable {
    let id: String
    var body: String?
    var state: String?
    var date: Date?
}

extension CustomerReviewModel {
    /// Shows `response` as this review's developer reply.
    mutating func applyResponse(_ response: CustomerReviewResponseModel) {
        responseId = response.id
        responseBody = response.body
        responseState = response.state
        responseDate = response.date
    }
}
