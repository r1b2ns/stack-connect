import Foundation
import StackCoreRust

/// Maps the store-agnostic Rust-core review records onto the app's models.
/// Shared by every provider backed by the core (App Store Connect, Google Play).
///
/// The core does no date logic, so the raw ISO8601 strings are parsed here. A
/// review id is passed through unchanged: for Google Play it is an opaque
/// composite (`{packageName}/{reviewId}`) the core needs back verbatim to reply,
/// so it must never be parsed or rebuilt.
enum CoreReviewMapper {

    /// Flattens the developer response into the model's `response*` fields.
    static func customerReview(_ review: StackCoreRust.CustomerReview) -> CustomerReviewModel {
        CustomerReviewModel(
            id: review.id,
            rating: Int(review.rating),
            title: review.title,
            body: review.body,
            reviewerNickname: review.reviewerNickname,
            createdDate: review.createdDate.flatMap(ISO8601DateParser.date(from:)),
            territory: review.territory,
            responseId: review.response?.id,
            responseBody: review.response?.body,
            responseState: review.response?.state,
            responseDate: review.response?.lastModifiedDate.flatMap(ISO8601DateParser.date(from:))
        )
    }

    static func page(_ page: StackCoreRust.CustomerReviewsPage) -> CustomerReviewsPageModel {
        CustomerReviewsPageModel(
            reviews: page.reviews.map(customerReview),
            nextPageToken: page.nextToken
        )
    }

    static func reviewResponse(_ response: StackCoreRust.ReviewResponse) -> CustomerReviewResponseModel {
        CustomerReviewResponseModel(
            id: response.id,
            body: response.body,
            state: response.state,
            date: response.lastModifiedDate.flatMap(ISO8601DateParser.date(from:))
        )
    }
}
