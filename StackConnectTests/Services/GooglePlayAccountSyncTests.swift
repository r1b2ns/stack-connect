import XCTest
import StackProtocols
@testable import StackConnect

/// The Google Play leg of the background sync (plan section 6, S1): edit-free
/// only (H2), scope filter, icons, release summaries, reviews saved next to the
/// App Store ones (H4) and the lightweight review rotation (H5).
final class GooglePlayAccountSyncTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var connection: MockGooglePlayAccountConnection!
    private let account = AccountModel(name: "Play Team", providerType: .googlePlay)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        connection = MockGooglePlayAccountConnection()
    }

    override func tearDown() async throws {
        storage = nil
        connection = nil
        try await super.tearDown()
    }

    private func sync(_ account: AccountModel? = nil, mode: SyncMode = .full) async -> SyncChange {
        await GooglePlayAccountSync(account: account ?? self.account, connection: connection, storage: storage, mode: mode).run()
    }

    private func cachedList(_ accountId: String? = nil) async throws -> [GooglePlayAppItem]? {
        try await storage.fetch([GooglePlayAppItem].self, id: GooglePlayAppItem.cacheKey(accountId: accountId ?? account.id))
    }

    // MARK: - No edit (H2)

    func testSyncNeverMakesAnEditBasedCall() async {
        connection.fetchAppsHandler = { [playApp("com.a"), playApp("com.b")] }
        connection.fetchReleaseSummariesHandler = { _, track in
            track == "production" ? [GooglePlayReleaseSummaryModel(track: track, name: "1.0", lifecycleState: .inReview, versionCodes: ["1"])] : []
        }

        _ = await sync(mode: .full)
        _ = await sync(mode: .lightweight)

        XCTAssertEqual(connection.editBasedReadCount, 0)
        XCTAssertTrue(connection.bundlesRequests.isEmpty)
        XCTAssertTrue(connection.releaseChanges.isEmpty)
        XCTAssertEqual(connection.fetchAppsCallCount, 2)
    }

    // MARK: - Apps

    func testSyncMergesAppsKeepsManualOnesAndFillsMissingIcons() async throws {
        let manual = GooglePlayAppItem(id: "com.manual", packageName: "com.manual", title: nil, isManuallyAdded: true)
        try await storage.save([manual], id: GooglePlayAppItem.cacheKey(accountId: account.id))
        connection.fetchAppsHandler = { [playApp("com.a", name: "Alpha")] }
        connection.fetchIconUrlHandler = { "https://play-lh.example/\($0)=s512" }

        _ = await sync()

        let list = try await cachedList()
        XCTAssertEqual(list?.map(\.packageName), ["com.a", "com.manual"])
        XCTAssertEqual(list?.first?.iconUrl, "https://play-lh.example/com.a=s512")
        let metadata = try await storage.fetch(SyncMetadata.self, id: "sync.account.\(account.id)")
        XCTAssertEqual(metadata?.appsSynced, 2)
        XCTAssertNil(metadata?.lastError)
    }

    func testSyncKeepsOnlyAppsInScope() async throws {
        let scoped = AccountModel(name: "Imported", providerType: .googlePlay, rules: .allPermissions,
                                  origin: .imported, appsBundles: ["com.shared"])
        connection.fetchAppsHandler = { [playApp("com.shared"), playApp("com.private")] }

        _ = await sync(scoped)

        let list = try await cachedList(scoped.id)
        XCTAssertEqual(list?.map(\.packageName), ["com.shared"])
        XCTAssertFalse(connection.releaseSummaryRequests.contains { $0.packageName == "com.private" })
        XCTAssertFalse(connection.reviewsPageRequests.contains { $0.packageName == "com.private" })
    }

    func testFailedListingRecordsErrorAndKeepsTheCachedList() async throws {
        let cached = [GooglePlayAppItem(id: "com.a", packageName: "com.a", title: "A", isManuallyAdded: false)]
        try await storage.save(cached, id: GooglePlayAppItem.cacheKey(accountId: account.id))
        connection.fetchAppsHandler = { throw URLError(.timedOut) }

        _ = await sync()

        let list = try await cachedList()
        XCTAssertEqual(list, cached)
        let metadata = try await storage.fetch(SyncMetadata.self, id: "sync.account.\(account.id)")
        XCTAssertNotNil(metadata?.lastError)
        XCTAssertTrue(connection.reviewsPageRequests.isEmpty)
    }

    // MARK: - Release summaries

    func testSyncCachesReleaseSummariesOfEveryStandardTrack() async throws {
        connection.fetchAppsHandler = { [playApp("com.a")] }
        connection.fetchReleaseSummariesHandler = { _, track in
            track == "production" ? [GooglePlayReleaseSummaryModel(track: track, name: "2.0", lifecycleState: .approvedNotPublished, versionCodes: ["20"])] : []
        }

        _ = await sync()

        XCTAssertEqual(Set(connection.releaseSummaryRequests.map(\.track)), Set(GooglePlayAppListSync.standardTracks))
        XCTAssertLessThanOrEqual(connection.maxSummaryFetchesInFlight, GooglePlayAccountSync.maxConcurrentSummaryFetches)
        let cache = try await storage.fetch(
            GooglePlayReleaseSummariesCache.self,
            id: GooglePlayReleaseSummariesCache.cacheKey(accountId: account.id, packageName: "com.a")
        )
        XCTAssertEqual(cache?.summaries.map(\.lifecycleState), [.approvedNotPublished])
    }

    func testSummariesAreSkippedWithoutTheVersionRule() async {
        let noVersion = AccountModel(name: "Imported", providerType: .googlePlay,
                                     rules: AccountRules(apps: AccountPermission.allCases, review: [.view]), origin: .imported)
        connection.fetchAppsHandler = { [playApp("com.a")] }

        _ = await sync(noVersion)

        XCTAssertTrue(connection.releaseSummaryRequests.isEmpty)
        XCTAssertEqual(connection.reviewsPageRequests.count, 1)
    }

    // MARK: - Reviews (H4)

    func testReviewsAreSavedAsCustomerReviewsKeyedByPackage() async throws {
        connection.fetchAppsHandler = { [playApp("com.a", name: "Alpha")] }
        connection.fetchReviewsPageHandler = { request in
            CustomerReviewsPageModel(reviews: [
                CustomerReviewModel(id: "\(request.packageName)/r1", rating: 4, body: "Nice", createdDate: Date())
            ], nextPageToken: nil)
        }

        let change = await sync()

        let stored = try await storage.fetch(CustomerReviewModel.self, id: "review.com.a.com.a/r1")
        XCTAssertEqual(stored?.appId, "com.a")
        XCTAssertEqual(change.newReviews.map(\.reviewId), ["com.a/r1"])
        XCTAssertEqual(change.newReviews.first?.appName, "Alpha")
        XCTAssertEqual(connection.reviewsPageRequests.first?.limit, 10)

        // Already stored: not new on the next run.
        let second = await sync()
        XCTAssertTrue(second.newReviews.isEmpty)
    }

    // MARK: - Quota rotation (H5)

    func testLightweightSyncReadsAtMostTwentyAppsPerRunAndRotates() async {
        let packages = (0..<25).map { String(format: "com.app%02d", $0) }
        connection.fetchAppsHandler = { packages.map { playApp($0) } }

        _ = await sync(mode: .lightweight)
        let firstRun = connection.reviewsPageRequests.map(\.packageName)
        XCTAssertEqual(Set(firstRun), Set(packages.prefix(20)))
        XCTAssertEqual(connection.reviewsPageRequests.first?.limit, 3)

        _ = await sync(mode: .lightweight)
        let secondRun = connection.reviewsPageRequests.dropFirst(20).map(\.packageName)
        XCTAssertEqual(Set(secondRun), Set(packages.suffix(5) + packages.prefix(15)))
    }

    func testFullSyncReadsEveryApp() async {
        let packages = (0..<25).map { "com.app\($0)" }
        connection.fetchAppsHandler = { packages.map { playApp($0) } }

        _ = await sync(mode: .full)

        XCTAssertEqual(Set(connection.reviewsPageRequests.map(\.packageName)), Set(packages))
    }

    func testRotationBatchWrapsAround() {
        let packages = ["a", "b", "c", "d", "e"]
        XCTAssertEqual(GooglePlayReviewRotation.batch(packages, cursor: 0, limit: 3).batch, ["a", "b", "c"])
        XCTAssertEqual(GooglePlayReviewRotation.batch(packages, cursor: 3, limit: 3).batch, ["d", "e", "a"])
        XCTAssertEqual(GooglePlayReviewRotation.batch(packages, cursor: 3, limit: 3).nextCursor, 1)
        XCTAssertEqual(GooglePlayReviewRotation.batch(packages, cursor: 9, limit: 10).batch, packages)
        XCTAssertTrue(GooglePlayReviewRotation.batch([], cursor: 2, limit: 3).batch.isEmpty)
    }
}

private func playApp(_ packageName: String, name: String? = nil) -> StackProtocols.AppInfo {
    StackProtocols.AppInfo(id: packageName, name: name ?? packageName, bundleId: packageName, platform: "ANDROID")
}
