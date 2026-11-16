import XCTest
@testable import StackConnect

/// The Home widgets load both stores (plan section 6, S3): In Review and
/// Awaiting Release from the Play release caches (H3), Recent Reviews from the
/// Play reviews saved by the sync (H4).
@MainActor
final class HomeWidgetGooglePlayTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private let apple = AccountModel(id: "asc", name: "ASC", providerType: .apple)
    private let play = AccountModel(id: "play", name: "Play", providerType: .googlePlay)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        try await storage.save(apple, id: apple.id)
        try await storage.save(play, id: play.id)
        let iosApp = AppModel(id: "1", name: "Pulse Timer", bundleId: "com.pulse", platform: "IOS", accountId: apple.id,
                              appStoreState: .waitingForReview, versionString: "3.1.0", lastModifiedDate: Date())
        try await storage.save(iosApp, id: "\(apple.id).\(iosApp.id)")
        let item = GooglePlayAppItem(id: "com.trailhead", packageName: "com.trailhead", title: "Trailhead", isManuallyAdded: false)
        try await storage.save([item], id: GooglePlayAppItem.cacheKey(accountId: play.id))
        let summaries = GooglePlayReleaseSummariesCache(accountId: play.id, packageName: item.packageName, summaries: [
            GooglePlayReleaseSummaryModel(track: "beta", name: "4.3.0-beta (4300)", lifecycleState: .inReview, versionCodes: ["4300"]),
            GooglePlayReleaseSummaryModel(track: "production", name: "4.2.0 (4210)", lifecycleState: .published, versionCodes: ["4210"])
        ], fetchedAt: Date())
        try await storage.save(summaries, id: summaries.cacheKey)
        let tracks = GooglePlayTracksCache(accountId: play.id, packageName: item.packageName, tracks: [
            GooglePlayTrackModel(track: "production", releases: [
                GooglePlayReleaseModel(name: "4.2.0 (4210)", status: .inProgress, versionCodes: ["4210"], userFraction: 0.2,
                                       releaseNotes: [], inAppUpdatePriority: nil)
            ])
        ])
        try await storage.save(tracks, id: tracks.cacheKey)
    }

    override func tearDown() async throws {
        storage = nil
        try await super.tearDown()
    }

    func testInReviewListsBothStoresWithTheAppStoreFirst() async {
        let widget = InReviewWidget(configuration: .init(kind: .inReview), storage: storage)
        await widget.load()

        XCTAssertEqual(widget.entries.map(\.name), ["Pulse Timer", "Trailhead"])
        XCTAssertEqual(widget.entries.map(\.platform), [.iOS, .android])
        XCTAssertEqual(widget.entries.last?.statusText, "Open testing · In review")
    }

    func testAwaitingReleaseShowsTheCachedRolloutWithItsFootnote() async {
        let widget = AwaitingReleaseWidget(configuration: .init(kind: .awaitingRelease), storage: storage)
        await widget.load()

        XCTAssertEqual(widget.entries.map(\.statusText), ["Production · Rolling out 20%"])
        XCTAssertTrue(widget.showsRolloutFootnote)
    }

    func testRecentReviewsMixesPlayReviewsWithAFootnote() async throws {
        var appleReview = CustomerReviewModel(id: "a1", rating: 5, title: "Great", createdDate: Date().addingTimeInterval(-3600 * 5))
        appleReview.appId = "1"
        var playReview = CustomerReviewModel(id: "com.trailhead/r1", rating: 2, body: "Crashes", createdDate: Date().addingTimeInterval(-3600 * 2))
        playReview.appId = "com.trailhead"
        try await storage.save(appleReview, id: CustomerReviewModel.storageId(appId: "1", reviewId: appleReview.id))
        try await storage.save(playReview, id: CustomerReviewModel.storageId(appId: "com.trailhead", reviewId: playReview.id))

        let widget = RecentReviewsWidget(configuration: .init(kind: .recentReviews), storage: storage)
        await widget.load()

        XCTAssertEqual(widget.reviews.map(\.review.id), ["com.trailhead/r1", "a1"])
        XCTAssertEqual(widget.reviews.first?.account, play)
        XCTAssertTrue(widget.showsGooglePlayFootnote)
    }

    func testAppleOnlyStoreShowsNoPlayFootnotes() async throws {
        try await storage.delete(AccountModel.self, id: play.id)

        let awaiting = AwaitingReleaseWidget(configuration: .init(kind: .awaitingRelease), storage: storage)
        await awaiting.load()
        let reviews = RecentReviewsWidget(configuration: .init(kind: .recentReviews), storage: storage)
        await reviews.load()

        XCTAssertTrue(awaiting.entries.isEmpty)
        XCTAssertFalse(awaiting.showsRolloutFootnote)
        XCTAssertFalse(reviews.showsGooglePlayFootnote)
    }
}
