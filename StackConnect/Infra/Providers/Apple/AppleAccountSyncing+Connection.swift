import Foundation
import StackHomeCore

// The `AppleAccountSyncing` protocol itself now lives in StackHomeCore (Foundation
// -pure, SDK-free) so that `SyncService` can move to core (T-A8 → T-A9). The
// concrete, App Store Connect SDK-backed conformance stays here in the iOS app
// target: `AppleAccountConnection` imports the ASC SDK and already provides
// `fetchApps`/`fetchIconUrl`/`fetchAppStoreVersions`/`fetchPhasedRelease`; this
// extension supplies the remaining `fetchRecentReviews` adapter.

extension AppleAccountConnection: AppleAccountSyncing {

    func fetchRecentReviews(appId: String, limit: Int) async throws -> [CustomerReviewModel] {
        try await fetchCustomerReviews(
            appId: appId,
            sort: "-createdDate",
            filterRating: nil,
            limit: limit
        )
    }
}
