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

    /// The package name embedded in a composite review id (`{package}/{id}`).
    func packageName(forReview reviewId: String) -> String? {
        reviews.first { $0.value.contains { $0.id == reviewId } }?.key
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
