import Foundation

/// Type-safe sort order for customer reviews, replacing the raw `String`
/// parameter in `AppleConnectionProtocol.fetchReviews`. Each case maps
/// to a concrete `Sort` value in the App Store Connect SDK; the mapping
/// is performed in the adapter (`WindowsAppleConnection`), keeping
/// `WindowsAppCore` SDK-free.
public enum ReviewSortOrder: Sendable, Hashable {
    /// Newest reviews first (`-createdDate`).
    case createdDateDescending
    /// Oldest reviews first (`createdDate`).
    case createdDateAscending
    /// Highest-rated reviews first (`-rating`).
    case ratingDescending
    /// Lowest-rated reviews first (`rating`).
    case ratingAscending
}
