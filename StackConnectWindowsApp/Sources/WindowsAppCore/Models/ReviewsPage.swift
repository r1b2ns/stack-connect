import Foundation
import StackHomeCore

/// A page of customer reviews returned by the connection, together with an
/// opaque cursor for requesting the next page.
///
/// The `cursor` is deliberately `String?` instead of `Any?` so the type stays
/// `Sendable` and fully serializable. The concrete `WindowsAppleConnection`
/// encodes the SDK's next-page URL as the cursor; other implementations can
/// choose their own encoding.
public struct ReviewsPage: Sendable {
    /// The reviews contained in this page.
    public let reviews: [CustomerReviewModel]

    /// Whether there are more pages available after this one.
    public let hasNextPage: Bool

    /// Opaque cursor token to pass back for fetching the next page.
    /// `nil` when this is the last page.
    public let cursor: String?

    public init(
        reviews: [CustomerReviewModel],
        hasNextPage: Bool,
        cursor: String? = nil
    ) {
        self.reviews = reviews
        self.hasNextPage = hasNextPage
        self.cursor = cursor
    }
}
