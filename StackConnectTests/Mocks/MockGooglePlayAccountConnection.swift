import Foundation
import StackProtocols
@testable import StackConnect

/// In-memory Google Play connection implementing every seam the Play screens use
/// (`GooglePlayAccountConnecting`, the edit-based app-content reads and the
/// reviews). Each call runs its handler, so a test can return canned data,
/// throw, or inspect the caller while it is suspended mid-call (e.g. to assert
/// the cached data is already on screen). Calls are counted and their arguments
/// recorded; `credentials` records what the factory was given.
final class MockGooglePlayAccountConnection: GooglePlayAccountConnecting,
    GooglePlayAppDetailsFetching,
    GooglePlayStoreListingsFetching,
    GooglePlayTracksFetching,
    GooglePlayReviewsConnecting,
    @unchecked Sendable {

    /// Arguments of one `fetchCustomerReviewsPage` call.
    struct ReviewsPageRequest: Equatable {
        let packageName: String
        let filterRating: Int?
        let limit: Int
        let pageToken: String?
    }

    /// What `validateCredentials()` does. Defaults to success.
    var validateHandler: @Sendable () async throws -> Void = {}

    /// What `fetchApps()` does. Defaults to an empty list.
    var fetchAppsHandler: @Sendable () async throws -> [StackProtocols.AppInfo] = { [] }

    /// What `fetchAppDetails(packageName:)` does. Defaults to empty details.
    var fetchAppDetailsHandler: @Sendable (String) async throws -> GooglePlayAppDetailsModel = {
        GooglePlayAppDetailsModel(packageName: $0)
    }

    /// What `fetchStoreListings(packageName:)` does. Defaults to no listing.
    var fetchStoreListingsHandler: @Sendable (String) async throws -> [GooglePlayStoreListingModel] = { _ in [] }

    /// What `fetchTracks(packageName:)` does. Defaults to no track.
    var fetchTracksHandler: @Sendable (String) async throws -> [GooglePlayTrackModel] = { _ in [] }

    /// What `fetchCustomerReviewsPage(...)` does. Defaults to an empty last page.
    var fetchReviewsPageHandler: @Sendable (ReviewsPageRequest) async throws -> CustomerReviewsPageModel = { _ in
        CustomerReviewsPageModel(reviews: [], nextPageToken: nil)
    }

    /// What `replyToReview(reviewId:body:)` does. Defaults to Google's upsert
    /// shape: the reply carries the review id and no state.
    var replyHandler: @Sendable (String, String) async throws -> CustomerReviewResponseModel = { reviewId, body in
        CustomerReviewResponseModel(id: reviewId, body: body, state: nil, date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private let lock = NSLock()
    private var _validateCallCount = 0
    private var _fetchAppsCallCount = 0
    private var _appDetailsRequests: [String] = []
    private var _storeListingsRequests: [String] = []
    private var _tracksRequests: [String] = []
    private var _reviewsPageRequests: [ReviewsPageRequest] = []
    private var _replies: [(reviewId: String, body: String)] = []
    private var _credentials: [GooglePlayCredentials] = []

    var validateCallCount: Int { lock.withLock { _validateCallCount } }
    var fetchAppsCallCount: Int { lock.withLock { _fetchAppsCallCount } }
    var appDetailsRequests: [String] { lock.withLock { _appDetailsRequests } }
    var storeListingsRequests: [String] { lock.withLock { _storeListingsRequests } }
    var tracksRequests: [String] { lock.withLock { _tracksRequests } }
    var reviewsPageRequests: [ReviewsPageRequest] { lock.withLock { _reviewsPageRequests } }
    var replies: [(reviewId: String, body: String)] { lock.withLock { _replies } }
    var credentials: [GooglePlayCredentials] { lock.withLock { _credentials } }

    /// Every edit-based read (app details, listings, tracks) made so far.
    var editBasedReadCount: Int {
        lock.withLock { _appDetailsRequests.count + _storeListingsRequests.count + _tracksRequests.count }
    }

    /// Factory closure for the ViewModels' `connectionFactory` parameters: records
    /// the credentials and hands back this mock.
    func factory(_ credentials: GooglePlayCredentials) -> any GooglePlayAccountConnecting {
        record(credentials)
        return self
    }

    /// Same as `factory`, typed for the app-details seam.
    func appDetailsFactory(_ credentials: GooglePlayCredentials) -> any GooglePlayAppDetailsFetching {
        record(credentials)
        return self
    }

    /// Same as `factory`, typed for the store-listings seam.
    func storeListingsFactory(_ credentials: GooglePlayCredentials) -> any GooglePlayStoreListingsFetching {
        record(credentials)
        return self
    }

    /// Same as `factory`, typed for the tracks seam.
    func tracksFactory(_ credentials: GooglePlayCredentials) -> any GooglePlayTracksFetching {
        record(credentials)
        return self
    }

    private func record(_ credentials: GooglePlayCredentials) {
        lock.withLock { _credentials.append(credentials) }
    }

    // MARK: - GooglePlayAccountConnecting

    func validateCredentials() async throws {
        lock.withLock { _validateCallCount += 1 }
        try await validateHandler()
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        lock.withLock { _fetchAppsCallCount += 1 }
        return try await fetchAppsHandler()
    }

    // MARK: - App content

    func fetchAppDetails(packageName: String) async throws -> GooglePlayAppDetailsModel {
        lock.withLock { _appDetailsRequests.append(packageName) }
        return try await fetchAppDetailsHandler(packageName)
    }

    func fetchStoreListings(packageName: String) async throws -> [GooglePlayStoreListingModel] {
        lock.withLock { _storeListingsRequests.append(packageName) }
        return try await fetchStoreListingsHandler(packageName)
    }

    func fetchTracks(packageName: String) async throws -> [GooglePlayTrackModel] {
        lock.withLock { _tracksRequests.append(packageName) }
        return try await fetchTracksHandler(packageName)
    }

    // MARK: - Reviews

    func fetchCustomerReviewsPage(
        packageName: String,
        filterRating: Int?,
        limit: Int,
        pageToken: String?
    ) async throws -> CustomerReviewsPageModel {
        let request = ReviewsPageRequest(packageName: packageName, filterRating: filterRating, limit: limit, pageToken: pageToken)
        lock.withLock { _reviewsPageRequests.append(request) }
        return try await fetchReviewsPageHandler(request)
    }

    func replyToReview(reviewId: String, body: String) async throws -> CustomerReviewResponseModel {
        lock.withLock { _replies.append((reviewId, body)) }
        return try await replyHandler(reviewId, body)
    }
}

/// In-memory `GooglePlayAppAccessChecking` for the manual "add app" flow.
final class MockGooglePlayAppAccessChecker: GooglePlayAppAccessChecking, @unchecked Sendable {

    /// Error `verifyAccess(packageName:)` throws; `nil` means access is granted.
    var error: Error?

    private let lock = NSLock()
    private var _checkedPackageNames: [String] = []

    var checkedPackageNames: [String] { lock.withLock { _checkedPackageNames } }

    func verifyAccess(packageName: String) async throws {
        lock.withLock { _checkedPackageNames.append(packageName) }
        if let error { throw error }
    }
}
