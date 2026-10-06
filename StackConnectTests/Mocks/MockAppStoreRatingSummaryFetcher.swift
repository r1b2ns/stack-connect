import Foundation
@testable import StackConnect

/// In-memory `AppStoreRatingSummaryFetching`: returns whatever `handler` gives
/// (no summary by default) and records each requested bundle id.
final class MockAppStoreRatingSummaryFetcher: AppStoreRatingSummaryFetching, @unchecked Sendable {

    var handler: @Sendable (String) async -> AppStoreRatingSummary? = { _ in nil }

    private let lock = NSLock()
    private var _requests: [String] = []

    var requests: [String] { lock.withLock { _requests } }

    func fetchSummary(bundleId: String) async -> AppStoreRatingSummary? {
        lock.withLock { _requests.append(bundleId) }
        return await handler(bundleId)
    }

    /// A summary over `ratings` as `(country, average, count)`.
    static func summary(_ ratings: [(String, Double, Int)], isComplete: Bool = true) -> AppStoreRatingSummary {
        AppStoreRatingSummary(
            storefronts: ratings.map { iTunesStorefrontInfo(country: $0.0, averageRating: $0.1, ratingCount: $0.2) },
            isComplete: isComplete
        )
    }
}
