import Foundation
import StackProtocols
@testable import StackConnect

final class MockAppleAccountSyncing: AppleAccountSyncing, @unchecked Sendable {

    var apps: [StackProtocols.AppInfo] = []
    var iconUrls: [String: String] = [:]
    var versions: [String: [AppStoreVersionModel]] = [:]
    var reviews: [String: [CustomerReviewModel]] = [:]
    var phasedReleases: [String: PhasedReleaseModel] = [:]
    /// When set, `fetchApps()` throws this instead of returning `apps`.
    var fetchAppsError: Error?

    private(set) var fetchedAppListCount = 0
    private(set) var fetchedVersionsForAppIds: [String] = []
    private(set) var fetchedIconForAppIds: [String] = []
    private(set) var fetchedReviewsForAppIds: [String] = []
    private(set) var fetchedPhasedForVersionIds: [String] = []

    private let lock = NSLock()

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        lock.lock(); defer { lock.unlock() }
        fetchedAppListCount += 1
        if let fetchAppsError { throw fetchAppsError }
        return apps
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
}
