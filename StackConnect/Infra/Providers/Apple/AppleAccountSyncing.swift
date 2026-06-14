import Foundation
import StackProtocols
import StackCoreRust    // BlobStore

/// Subset of `AppleAccountConnection` used by `SyncService`. Carved out so the
/// service can be unit-tested with a mock connection.
protocol AppleAccountSyncing: Sendable {
    /// Validates credentials once up front so the underlying connection seeds its
    /// `self.provider`. Calling this before the parallel enrichment task group
    /// prevents the concurrent Swift-only fetch methods from each lazily
    /// triggering their own `validateCredentials()` (the validate storm behind #84).
    func validateCredentials() async throws
    func fetchApps() async throws -> [StackProtocols.AppInfo]

    /// Fetches the account's apps. When the Rust-core flag is ON, the core
    /// SyncService also persists each app as a base AppModel blob into `store`
    /// (merging with any existing AppModel to preserve enrichment/user fields);
    /// when OFF this behaves exactly like `fetchApps()` and ignores `store`.
    func syncApps(accountId: String, store: BlobStore) async throws -> [StackProtocols.AppInfo]
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
