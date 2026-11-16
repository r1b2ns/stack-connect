#if DEBUG
import Foundation
import StackCoreRust

/// In-memory Google Play provider. Serves the same capabilities the real core
/// exposes for Play (`[.apps, .reviews, .appDetails, .storeListings, .tracks,
/// .appIcons]`) from one `FakeGooglePlayDeveloper`.
///
/// Extending it for a new Play capability: override the capability accessor
/// here, add a `FakePlay…` subclass of the core's handle below that overrides
/// **every** `open func` of that handle (an un-overridden method calls into Rust
/// with a null handle and crashes), and seed its data in `FakeGooglePlayCatalog`.
final class FakeGooglePlayProvider: FakeCoreProvider, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(kind: .googlePlay)
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake core providers are never lifted from the FFI")
    }

    override func capabilities() -> [Capability] {
        [.apps, .reviews, .appDetails, .storeListings, .tracks, .appIcons]
    }

    override func fetchApps() async throws -> [AppInfo] {
        developer.state.read { $0.apps }
    }

    override func appDetails() -> AppDetails? { FakePlayAppDetails(developer: developer) }
    override func appIcons() -> AppIcons? { FakePlayAppIcons(developer: developer) }
    override func reviews() -> Reviews? { FakePlayReviews(developer: developer) }
    override func storeListings() -> StoreListings? { FakePlayStoreListings(developer: developer) }
    override func tracks() -> Tracks? { FakePlayTracks(developer: developer) }
}

// MARK: - App details

final class FakePlayAppDetails: AppDetails, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    /// Also the "can this account reach package X?" check of a manual add:
    /// an unknown package is a 404, like Google's answer.
    override func fetchAppDetails(appId: String) async throws -> AppDetailsInfo {
        try developer.state.read { state in
            guard let details = state.details[appId] else { throw FakeCoreError.notFound("Package \(appId)") }
            return details
        }
    }
}

// MARK: - App icons

final class FakePlayAppIcons: AppIcons, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchIconUrl(appId: String) async throws -> String? {
        developer.state.read { $0.iconUrls[appId] }
    }
}

// MARK: - Store listings

final class FakePlayStoreListings: StoreListings, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchStoreListings(appId: String) async throws -> [StoreListingInfo] {
        try developer.state.read { state in
            guard let listings = state.listings[appId] else { throw FakeCoreError.notFound("Package \(appId)") }
            return listings
        }
    }
}

// MARK: - Tracks

final class FakePlayTracks: Tracks, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchTracks(appId: String) async throws -> [TrackInfo] {
        try developer.state.read { state in
            guard let tracks = state.tracks[appId] else { throw FakeCoreError.notFound("Package \(appId)") }
            return tracks
        }
    }
}

// MARK: - Reviews

final class FakePlayReviews: Reviews, @unchecked Sendable {

    private let developer: FakeGooglePlayDeveloper

    init(developer: FakeGooglePlayDeveloper) {
        self.developer = developer
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Fake capabilities are never lifted from the FFI")
    }

    override func fetchCustomerReviews(appId: String) async throws -> [CustomerReview] {
        developer.state.read { FakeReviewPaging.sorted($0.reviews[appId] ?? [], by: "-createdDate") }
    }

    /// Google serves newest first only; the core rejects any other sort.
    override func fetchCustomerReviewsPage(appId: String, sort: String, filterRating: [String], limit: UInt32, pageToken: String?) async throws -> CustomerReviewsPage {
        guard sort == "-createdDate" else { throw FakeCoreError.unsupported("Sorting Google Play reviews by \(sort)") }
        let ratings = Set(filterRating.compactMap(Int32.init))
        let all = developer.state.read { state in
            FakeReviewPaging.sorted(state.reviews[appId] ?? [], by: sort).filter { ratings.isEmpty || ratings.contains($0.rating) }
        }
        return FakeReviewPaging.page(all, limit: limit, pageToken: pageToken)
    }

    /// An upsert: replying again replaces the previous reply. Google rejects
    /// replies over 350 characters with an HTTP 400.
    override func replyToReview(reviewId: String, body: String) async throws -> ReviewResponse {
        guard body.count <= 350 else {
            throw StackError.Http(status: 400, message: "Reply text is too long (fake data).")
        }
        let response = ReviewResponse(id: "\(reviewId)/reply", body: body, state: nil, lastModifiedDate: FakeClock.iso(Date()))
        try developer.state.write { state in
            guard let packageName = state.packageName(forReview: reviewId),
                  let index = state.reviews[packageName]?.firstIndex(where: { $0.id == reviewId }) else {
                throw FakeCoreError.notFound("Review \(reviewId)")
            }
            state.reviews[packageName]![index].response = response
        }
        return response
    }

    override func deleteReviewResponse(responseId: String) async throws {
        throw FakeCoreError.unsupported("Deleting a Google Play reply")
    }

    override func fetchReviewSubmissions(appId: String) async throws -> [ReviewSubmission] {
        throw FakeCoreError.unsupported("Review submissions")
    }

    override func submitReviewSubmission(submissionId: String) async throws {
        throw FakeCoreError.unsupported("Review submissions")
    }

    override func discardReviewSubmission(submissionId: String) async throws {
        throw FakeCoreError.unsupported("Review submissions")
    }
}
#endif
