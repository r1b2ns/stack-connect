import Foundation
@testable import StackConnect

/// In-memory `AppleReviewsConnecting`. Every call is recorded in order (so tests
/// can assert delete-then-create on edit) and runs its handler.
final class MockAppleReviewsConnection: AppleReviewsConnecting, @unchecked Sendable {

    enum Call: Equatable {
        case fetchPage(appId: String, sort: String, filterRating: [String]?, limit: Int, pageToken: String?)
        case reply(reviewId: String, body: String)
        case deleteResponse(responseId: String)
    }

    /// What `fetchCustomerReviewsPage` returns. Defaults to an empty last page.
    var pageHandler: @Sendable () async throws -> AppleAccountConnection.CustomerReviewsPage = {
        AppleAccountConnection.CustomerReviewsPage(reviews: [], hasNextPage: false, rawResponse: nil)
    }

    /// What `replyToReview` returns. Defaults to a fresh, pending response.
    var replyHandler: @Sendable (String, String) async throws -> CustomerReviewResponseModel = { _, body in
        CustomerReviewResponseModel(id: "resp-new", body: body, state: "PENDING_PUBLISH", date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// Error `deleteReviewResponse` throws; `nil` means success.
    var deleteError: Error?

    private let lock = NSLock()
    private var _calls: [Call] = []

    var calls: [Call] { lock.withLock { _calls } }

    private func record(_ call: Call) {
        lock.withLock { _calls.append(call) }
    }

    func fetchCustomerReviewsPage(
        appId: String,
        sort: String,
        filterRating: [String]?,
        limit: Int,
        pageAfterResponse: Any?
    ) async throws -> AppleAccountConnection.CustomerReviewsPage {
        record(.fetchPage(appId: appId, sort: sort, filterRating: filterRating, limit: limit, pageToken: pageAfterResponse as? String))
        return try await pageHandler()
    }

    func replyToReview(reviewId: String, responseBody: String) async throws -> CustomerReviewResponseModel {
        record(.reply(reviewId: reviewId, body: responseBody))
        return try await replyHandler(reviewId, responseBody)
    }

    func deleteReviewResponse(responseId: String) async throws {
        record(.deleteResponse(responseId: responseId))
        if let deleteError { throw deleteError }
    }
}
