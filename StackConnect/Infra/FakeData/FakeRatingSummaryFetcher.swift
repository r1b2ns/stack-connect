#if DEBUG
import Foundation

/// App Store rating summary in fake data mode: the per-storefront ratings
/// seeded for each app (`FakeASCAppSeed.storefrontRatings`), instead of
/// sweeping the public iTunes Lookup API.
struct FakeRatingSummaryFetcher: AppStoreRatingSummaryFetching {

    func fetchSummary(bundleId: String) async -> AppStoreRatingSummary? {
        let ratings = FakeAppStoreConnectCatalog.allAppSeeds.first { $0.bundleId == bundleId }?.storefrontRatings ?? [:]
        let storefronts = ratings
            .map { iTunesStorefrontInfo(country: $0.key, averageRating: $0.value.0, ratingCount: $0.value.1) }
            .sorted { $0.country < $1.country }
        return AppStoreRatingSummary(storefronts: storefronts, isComplete: true)
    }
}
#endif
