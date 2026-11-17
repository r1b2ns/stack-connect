import Foundation

/// The review calls of `AppleAccountConnection` that `AppleCustomerReviewsService`
/// uses (mirrors `GooglePlayReviewsConnecting`), so the service can be
/// unit-tested with a mock connection (no keychain, network or Rust core).
protocol AppleReviewsConnecting: Sendable {
    /// One page of reviews. `pageAfterResponse` is the previous page's
    /// `rawResponse` (the core's opaque `nextToken` String), `nil` for the first.
    func fetchCustomerReviewsPage(
        appId: String,
        sort: String,
        filterRating: [String]?,
        limit: Int,
        pageAfterResponse: Any?
    ) async throws -> AppleAccountConnection.CustomerReviewsPage

    /// Creates the developer response and returns the one App Store Connect kept.
    func replyToReview(reviewId: String, responseBody: String) async throws -> CustomerReviewResponseModel

    func deleteReviewResponse(responseId: String) async throws
}

extension AppleAccountConnection: AppleReviewsConnecting {}

/// App Store Connect reviews through `AppleAccountConnection` (Rust core).
///
/// Keeps the behaviour the review screens had before the provider seam:
/// every sort order, reply deletion, edit = delete + create, and the same
/// error copy.
struct AppleCustomerReviewsService: CustomerReviewsServicing {

    let connection: any AppleReviewsConnecting

    var traits: CustomerReviewsTraits { .appStore }

    func fetchReviewsPage(
        appId: String,
        sort: ReviewSortOption,
        filterRating: Int?,
        limit: Int,
        pageToken: String?
    ) async throws -> CustomerReviewsPageModel {
        let page = try await connection.fetchCustomerReviewsPage(
            appId: appId,
            sort: sort.rawValue,
            filterRating: filterRating.map { [String($0)] },
            limit: limit,
            pageAfterResponse: pageToken
        )
        // The connection's opaque paging token is the core's `nextToken` String.
        return CustomerReviewsPageModel(reviews: page.reviews, nextPageToken: page.rawResponse as? String)
    }

    /// App Store Connect has no PATCH for replies: editing deletes the existing
    /// response first, then creates a new one with the updated text.
    func reply(
        toReviewId reviewId: String,
        body: String,
        replacingResponseId: String?
    ) async throws -> CustomerReviewResponseModel {
        if let replacingResponseId {
            try await connection.deleteReviewResponse(responseId: replacingResponseId)
        }
        let response = try await connection.replyToReview(reviewId: reviewId, responseBody: body)
        // A fresh response waits for Apple's moderation; keep showing "Pending"
        // when the API leaves the state or date out.
        return CustomerReviewResponseModel(
            id: response.id,
            body: response.body ?? body,
            state: response.state ?? "PENDING_PUBLISH",
            date: response.date ?? Date()
        )
    }

    func deleteReply(responseId: String) async throws {
        try await connection.deleteReviewResponse(responseId: responseId)
    }

    func message(for error: Error, operation: CustomerReviewsOperation) -> String {
        switch operation {
        case .load:        return error.localizedDescription
        case .reply:       return String(localized: "Failed to send reply")
        case .deleteReply: return String(localized: "Failed to delete reply")
        }
    }
}
