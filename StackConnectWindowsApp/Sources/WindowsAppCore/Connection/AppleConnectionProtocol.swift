import Foundation
import StackProtocols
import StackHomeCore

/// Rich, mockable connection protocol for App Store Connect operations needed
/// by the Windows GUI feature set (apps list, users, reviews with pagination,
/// review replies).
///
/// This protocol is **Foundation-pure**: it imports only `StackProtocols` and
/// `StackHomeCore` model types, never the App Store Connect SDK itself. The
/// concrete SDK-backed adapter (`WindowsAppleConnection`) lives in the
/// executable target and conforms to this protocol.
///
/// All methods are `async throws` so callers handle network errors uniformly.
/// The protocol is `Sendable` so it can be held by `@MainActor`-isolated models
/// and passed across isolation boundaries.
///
/// ## Pagination
///
/// `fetchReviews` returns a `ReviewsPage` that carries an opaque `cursor`.
/// To fetch the next page, pass the cursor back via the `cursor` parameter.
/// Pass `nil` (or omit) for the first page.
public protocol AppleConnectionProtocol: Sendable {

    // MARK: - Credentials

    /// Validates that the stored credentials are accepted by the API.
    func validateCredentials() async throws

    // MARK: - Apps

    /// Fetches all apps visible to the authenticated account.
    func fetchApps() async throws -> [AppInfo]

    // MARK: - Users

    /// Fetches all team members (active users + pending invitations).
    func fetchUsers() async throws -> [UserModel]

    // MARK: - Reviews (paginated)

    /// Fetches a page of customer reviews for the given app.
    ///
    /// - Parameters:
    ///   - appId: The App Store app identifier.
    ///   - sort: Sort order string, e.g. `"-createdDate"` (default).
    ///   - filterRating: Optional rating filter (e.g. `["1", "2"]`).
    ///   - limit: Maximum reviews per page (default 50).
    ///   - cursor: Opaque pagination cursor from a previous `ReviewsPage`.
    ///             Pass `nil` for the first page.
    /// - Returns: A `ReviewsPage` containing the reviews and pagination info.
    func fetchReviews(
        appId: String,
        sort: String,
        filterRating: [String]?,
        limit: Int,
        cursor: String?
    ) async throws -> ReviewsPage

    // MARK: - Review Replies

    /// Creates a new reply or updates an existing reply for a customer review.
    ///
    /// The underlying API distinguishes create vs. update; this method
    /// intentionally combines both under "upsert" semantics so callers do not
    /// need to track whether a response already exists.
    ///
    /// - Parameters:
    ///   - reviewId: The customer review identifier to reply to.
    ///   - responseBody: The text of the reply.
    func upsertReply(reviewId: String, responseBody: String) async throws

    /// Deletes an existing reply to a customer review.
    ///
    /// - Parameter responseId: The review-response identifier to delete.
    func deleteReply(responseId: String) async throws
}

// MARK: - Convenience Defaults

public extension AppleConnectionProtocol {

    /// Fetches the first page of reviews with default sort and no rating filter.
    func fetchReviews(
        appId: String,
        sort: String = "-createdDate",
        filterRating: [String]? = nil,
        limit: Int = 50,
        cursor: String? = nil
    ) async throws -> ReviewsPage {
        try await fetchReviews(
            appId: appId,
            sort: sort,
            filterRating: filterRating,
            limit: limit,
            cursor: cursor
        )
    }
}
