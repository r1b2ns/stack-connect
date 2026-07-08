import Foundation
import StackProtocols
import StackCoreRust    // BlobStore
@testable import StackConnect

final class MockAppleAccountSyncing: AppleAccountSyncing, @unchecked Sendable {

    var apps: [StackProtocols.AppInfo] = []
    var iconUrls: [String: String] = [:]
    var versions: [String: [AppStoreVersionModel]] = [:]
    var reviews: [String: [CustomerReviewModel]] = [:]
    var phasedReleases: [String: PhasedReleaseModel] = [:]
    var builds: [String: [BuildModel]] = [:]
    /// When set, `fetchApps()` throws this instead of returning `apps`.
    var fetchAppsError: Error?
    /// When set, `validateCredentials()` throws this instead of succeeding.
    var validateCredentialsError: Error?

    private(set) var validateCredentialsCount = 0
    private(set) var fetchedAppListCount = 0
    private(set) var fetchedVersionsForAppIds: [String] = []
    private(set) var fetchedIconForAppIds: [String] = []
    private(set) var fetchedReviewsForAppIds: [String] = []
    private(set) var fetchedPhasedForVersionIds: [String] = []
    private(set) var fetchedBuildsForAppIds: [String] = []

    private let lock = NSLock()

    func validateCredentials() async throws {
        lock.lock(); defer { lock.unlock() }
        validateCredentialsCount += 1
        if let validateCredentialsError { throw validateCredentialsError }
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        lock.lock(); defer { lock.unlock() }
        fetchedAppListCount += 1
        if let fetchAppsError { throw fetchAppsError }
        return apps
    }

    /// Mirrors flag-OFF parity: ignores `store` and returns the canned apps
    /// exactly like `fetchApps()` (same error + counter behavior).
    func syncApps(accountId: String, store: BlobStore) async throws -> [StackProtocols.AppInfo] {
        try await fetchApps()
    }

    func fetchIconUrl(appId: String) async -> String? {
        lock.lock(); defer { lock.unlock() }
        fetchedIconForAppIds.append(appId)
        return iconUrls[appId]
    }

    func fetchAppStoreVersions(appId: String, limit: Int) async throws -> [AppStoreVersionModel] {
        lock.lock(); defer { lock.unlock() }
        fetchedVersionsForAppIds.append(appId)
        return Array((versions[appId] ?? []).prefix(limit))
    }

    func fetchRecentReviews(appId: String, limit: Int) async throws -> [CustomerReviewModel] {
        lock.lock(); defer { lock.unlock() }
        fetchedReviewsForAppIds.append(appId)
        return Array((reviews[appId] ?? []).prefix(limit))
    }

    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel? {
        lock.lock(); defer { lock.unlock() }
        fetchedPhasedForVersionIds.append(versionId)
        return phasedReleases[versionId]
    }

    func fetchBuilds(appId: String, limit: Int) async throws -> [BuildModel] {
        lock.lock(); defer { lock.unlock() }
        fetchedBuildsForAppIds.append(appId)
        return Array((builds[appId] ?? []).prefix(limit))
    }
}
