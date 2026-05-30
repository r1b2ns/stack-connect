import Foundation
import StackProtocols

/// Subset of `AppleAccountConnection` used by `SyncService`. Carved out so the
/// service can be unit-tested with a mock connection.
protocol AppleAccountSyncing: Sendable {
    func fetchApps() async throws -> [StackProtocols.AppInfo]
    func fetchIconUrl(appId: String) async -> String?
    func fetchAppStoreVersions(appId: String, limit: Int) async throws -> [AppStoreVersionModel]
    func fetchRecentReviews(appId: String, limit: Int) async throws -> [CustomerReviewModel]
    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel?
}

// MARK: - Default conformance for the real connection

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
