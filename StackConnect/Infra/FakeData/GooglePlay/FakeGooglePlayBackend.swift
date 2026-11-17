#if DEBUG
import Foundation
import StackCoreRust

/// Everything one fake Google Play developer account (service account) holds,
/// in the core's wire shapes.
///
/// To fake a new Play capability (release summaries, bundles, track mutations,
/// users…), add its data here, seed it in `FakeGooglePlayCatalog` and serve it
/// from a capability subclass in `FakeGooglePlayProvider.swift`.
struct FakeGooglePlayState {
    var apps: [AppInfo] = []
    var iconUrls: [String: String] = [:]                     // package name
    var details: [String: AppDetailsInfo] = [:]              // package name
    var listings: [String: [StoreListingInfo]] = [:]         // package name
    var tracks: [String: [TrackInfo]] = [:]                  // package name
    var reviews: [String: [CustomerReview]] = [:]            // package name
    /// Lifecycle state (`RELEASE_LIFECYCLE_STATE_*`) of every release, keyed by
    /// package name, then by `releaseKey(track:versionCodes:)`.
    var lifecycles: [String: [String: String]] = [:]
    var bundles: [String: [BundleInfo]] = [:]                // package name
    /// Users of the developer account (`developers/{id}/users`).
    var users: [PlayUserInfo] = []
    /// Every `tracks.releases.list` answers with Google's quota error
    /// (`-StackFakePlayQuota YES`).
    var releaseSummariesQuotaExceeded = false

    /// The package name embedded in a composite review id (`{package}/{id}`).
    func packageName(forReview reviewId: String) -> String? {
        reviews.first { $0.value.contains { $0.id == reviewId } }?.key
    }

    /// Raw `releaseLifecycleState` values of `tracks.releases.list`.
    enum Lifecycle {
        static let draft = "RELEASE_LIFECYCLE_STATE_DRAFT"
        static let notSentForReview = "RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW"
        static let inReview = "RELEASE_LIFECYCLE_STATE_IN_REVIEW"
        static let published = "RELEASE_LIFECYCLE_STATE_PUBLISHED"
    }

    /// A release is identified by its track and sorted version codes (plan R7).
    static func releaseKey(track: String, versionCodes: [String]) -> String {
        "\(track)|\(versionCodes.sorted().joined(separator: ","))"
    }

    /// `tracks.releases.list` for one track: one summary per release, in track
    /// order. An unknown track has no releases (Google answers 404, which the
    /// core maps to an empty list).
    func releaseSummaries(packageName: String, track: String) -> [ReleaseSummaryInfo] {
        guard let releases = tracks[packageName]?.first(where: { $0.track == track })?.releases else { return [] }
        let states = lifecycles[packageName] ?? [:]
        return releases.map { release in
            ReleaseSummaryInfo(
                track: track,
                name: release.name,
                lifecycleState: states[Self.releaseKey(track: track, versionCodes: release.versionCodes)],
                versionCodes: release.versionCodes
            )
        }
    }
}

/// One fake Play developer account.
final class FakeGooglePlayDeveloper: @unchecked Sendable {

    let clientEmail: String
    let clock: FakeClock
    let state: FakeStateBox<FakeGooglePlayState>

    init(clientEmail: String, clock: FakeClock, state: FakeGooglePlayState) {
        self.clientEmail = clientEmail
        self.clock = clock
        self.state = FakeStateBox(state)
    }
}

/// Every fake Play developer account of the session, keyed by the service
/// account's `client_email`.
final class FakeGooglePlayBackend: @unchecked Sendable {

    private let lock = NSLock()
    private var developers: [String: FakeGooglePlayDeveloper]
    private let clock: FakeClock

    init(clock: FakeClock, developers: [FakeGooglePlayDeveloper]) {
        self.clock = clock
        self.developers = Dictionary(uniqueKeysWithValues: developers.map { ($0.clientEmail, $0) })
    }

    /// The account for `clientEmail`; an unknown service account (added while
    /// in fake mode) gets an empty one.
    func developer(clientEmail: String) -> FakeGooglePlayDeveloper {
        lock.withLock {
            if let developer = developers[clientEmail] { return developer }
            let developer = FakeGooglePlayDeveloper(clientEmail: clientEmail, clock: clock, state: FakeGooglePlayState())
            developers[clientEmail] = developer
            return developer
        }
    }
}
#endif
