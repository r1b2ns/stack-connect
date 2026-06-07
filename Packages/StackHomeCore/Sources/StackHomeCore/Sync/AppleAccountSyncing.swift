import Foundation
import StackProtocols

/// Foundation-pure abstraction over Apple account syncing, used by
/// `SyncService` (extracted to core in T-A9). It is the seam that lets the sync
/// pipeline live in core without depending on the App Store Connect SDK: the
/// concrete, SDK-backed conformance (`AppleAccountConnection`) stays in the iOS
/// app target and imports the ASC SDK, while core only knows this protocol and
/// the Foundation-pure value models it exchanges.
///
/// Every type in this surface is SDK-free: `AppInfo` (StackProtocols),
/// `AppStoreVersionModel` / `PhasedReleaseModel` / `CustomerReviewModel`
/// (StackHomeCore value models). No `import AppStoreConnect` here.
public protocol AppleAccountSyncing: Sendable {
    func fetchApps() async throws -> [AppInfo]
    func fetchIconUrl(appId: String) async -> String?
    func fetchAppStoreVersions(appId: String, limit: Int) async throws -> [AppStoreVersionModel]
    func fetchRecentReviews(appId: String, limit: Int) async throws -> [CustomerReviewModel]
    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel?
}
