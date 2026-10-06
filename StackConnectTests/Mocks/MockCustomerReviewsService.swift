import Foundation
@testable import StackConnect

/// In-memory `CustomerReviewsServicing` with configurable store traits (App
/// Store by default). Records every call so tests can assert what the review
/// screens asked the store for.
final class MockCustomerReviewsService: CustomerReviewsServicing, @unchecked Sendable {

    struct PageRequest: Equatable {
        let appId: String
        let sort: ReviewSortOption
        let filterRating: Int?
        let pageToken: String?
    }

    struct ReplyRequest: Equatable {
        let reviewId: String
        let body: String
        let replacingResponseId: String?
    }

    let traits: CustomerReviewsTraits

    var pageHandler: @Sendable (PageRequest) async throws -> CustomerReviewsPageModel = { _ in
        CustomerReviewsPageModel(reviews: [], nextPageToken: nil)
    }

    var replyHandler: @Sendable (ReplyRequest) async throws -> CustomerReviewResponseModel = { request in
        CustomerReviewResponseModel(id: "resp-\(request.reviewId)", body: request.body, state: "PENDING_PUBLISH", date: Date())
    }

    var deleteError: Error?

    /// Prefix of `message(for:operation:)`, which echoes the operation so tests
    /// can tell the copies apart.
    static func message(for operation: CustomerReviewsOperation) -> String {
        "mock-\(operation)"
    }

    private let lock = NSLock()
    private var _pageRequests: [PageRequest] = []
    private var _replyRequests: [ReplyRequest] = []
    private var _deletedResponseIds: [String] = []

    var pageRequests: [PageRequest] { lock.withLock { _pageRequests } }
    var replyRequests: [ReplyRequest] { lock.withLock { _replyRequests } }
    var deletedResponseIds: [String] { lock.withLock { _deletedResponseIds } }

    init(traits: CustomerReviewsTraits = .appStore) {
        self.traits = traits
    }

    func fetchReviewsPage(
        appId: String,
        sort: ReviewSortOption,
        filterRating: Int?,
        limit: Int,
        pageToken: String?
    ) async throws -> CustomerReviewsPageModel {
        let request = PageRequest(appId: appId, sort: sort, filterRating: filterRating, pageToken: pageToken)
        lock.withLock { _pageRequests.append(request) }
        return try await pageHandler(request)
    }

    func reply(
        toReviewId reviewId: String,
        body: String,
        replacingResponseId: String?
    ) async throws -> CustomerReviewResponseModel {
        let request = ReplyRequest(reviewId: reviewId, body: body, replacingResponseId: replacingResponseId)
        lock.withLock { _replyRequests.append(request) }
        return try await replyHandler(request)
    }

    func deleteReply(responseId: String) async throws {
        lock.withLock { _deletedResponseIds.append(responseId) }
        if let deleteError { throw deleteError }
    }

    func message(for error: Error, operation: CustomerReviewsOperation) -> String {
        Self.message(for: operation)
    }
}
