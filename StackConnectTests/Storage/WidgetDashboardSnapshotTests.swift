import XCTest
import StackCore
@testable import StackConnect

/// The WidgetKit snapshot (plan section 6, S6, H6): written by the app from the
/// in-app builders, read by the extension. The Apple-only tests pin the rows the
/// home-screen widgets drew before (one per platform version, phased day x of 7)
/// plus the rows the extension's own categorizer used to miss.
@MainActor
final class WidgetDashboardSnapshotTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var directory: URL!
    private let account = AccountModel(id: "asc", name: "ASC", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetDashboardSnapshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await storage.save(account, id: account.id)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        storage = nil
        try await super.tearDown()
    }

    private var fileURL: URL { directory.appendingPathComponent(WidgetDashboardSnapshotStore.fileName) }

    private func save(_ app: AppModel) async throws {
        try await storage.save(app, id: "\(app.accountId).\(app.id)")
    }

    private func snapshot() async throws -> WidgetDashboardSnapshot {
        WidgetDashboardSnapshotWriter.snapshot(from: try await WidgetDashboardSnapshotWriter.loadLists(storage: storage, featureFlags: .googlePlayOn))
    }

    // MARK: - Round trip

    func testSnapshotRoundTripsThroughTheFile() throws {
        let original = WidgetDashboardSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            inReview: [WidgetDashboardRow(id: "1", name: "Pulse", iconUrl: "https://icon", platform: .iOS, statusText: "Waiting for Review",
                                          statusColor: .orange, versionText: "3.1.0", progress: nil, deepLink: "stackconnect://app/a/1")],
            awaitingRelease: [WidgetDashboardRow(id: "2", name: "Trailhead", iconUrl: nil, platform: .android, statusText: "Production · Rolling out 20%",
                                                 statusColor: .blue, versionText: "4.2.0",
                                                 progress: .rollout(fraction: 0.2, halted: false, asOf: Date(timeIntervalSince1970: 1_799_000_000)),
                                                 deepLink: nil)],
            awaitingReleaseCount: 7,
            recentReviews: [WidgetDashboardReview(id: "r", appName: "Trailhead", iconUrl: nil, platform: .android, rating: 2, title: nil,
                                                  body: "Crashes", createdDate: Date(timeIntervalSince1970: 1_799_500_000), hasResponse: true, deepLink: nil)]
        )

        try WidgetDashboardSnapshotStore.save(original, to: fileURL)

        XCTAssertEqual(WidgetDashboardSnapshotStore.load(from: fileURL), original)
        XCTAssertEqual(original.reviewPlatforms, [.android])
    }

    func testMissingOrForeignFileReadsAsNoSnapshot() throws {
        XCTAssertNil(WidgetDashboardSnapshotStore.load(from: fileURL))
        try Data("{\"version\": 99}".utf8).write(to: fileURL)
        XCTAssertNil(WidgetDashboardSnapshotStore.load(from: fileURL))
    }

    func testWriteSavesTheSnapshotFile() async throws {
        try await save(AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", platform: "IOS", accountId: account.id,
                                appStoreState: .waitingForReview, versionString: "3.1.0"))

        await WidgetDashboardSnapshotWriter.write(storage: storage, to: fileURL)

        XCTAssertEqual(WidgetDashboardSnapshotStore.load(from: fileURL)?.inReview.map(\.name), ["Pulse"])
    }

    // MARK: - Apple-only regression

    func testAppleOnlyStoreDrawsOneRowPerPlatformVersionLikeBefore() async throws {
        try await save(AppModel(
            id: "1", name: "Ledger", bundleId: "com.ledger", platform: "IOS", accountId: account.id,
            appStoreState: .inReview, versionString: "2.7.0", lastModifiedDate: Date(),
            platformVersions: [
                AppPlatformVersion(platform: "IOS", appStoreState: .inReview, versionString: "2.7.0", id: "v-ios"),
                AppPlatformVersion(platform: "TV_OS", appStoreState: .invalidBinary, versionString: "2.7.1", id: "v-tv")
            ]
        ))
        try await save(AppModel(
            id: "2", name: "Mosaic", bundleId: "com.mosaic", platform: "IOS", accountId: account.id,
            appStoreState: .pendingDeveloperRelease, versionString: "5.1.0",
            platformVersions: [AppPlatformVersion(platform: "IOS", appStoreState: .pendingDeveloperRelease, versionString: "5.1.0", id: "v-m")],
            awaitingVersions: [AppPlatformVersion(platform: "IOS", appStoreState: .pendingDeveloperRelease, versionString: "5.1.0", id: "v-m")]
        ))

        let snapshot = try await snapshot()

        XCTAssertEqual(snapshot.inReview.map(\.platform), [.iOS, .tvOS])
        XCTAssertEqual(snapshot.inReview.map(\.statusText), [AppStoreState.inReview.displayName, AppStoreState.invalidBinary.displayName])
        XCTAssertEqual(snapshot.inReview.map(\.statusColor), [.orange, .red])
        XCTAssertEqual(snapshot.inReview.map(\.versionText), ["2.7.0", "2.7.1"])
        XCTAssertEqual(snapshot.inReview.first?.deepLink, DeepLink.app(accountId: account.id, appId: "1").url.absoluteString)
        XCTAssertEqual(snapshot.awaitingRelease.map(\.name), ["Mosaic"])
        XCTAssertEqual(snapshot.awaitingRelease.first?.statusColor, .yellow)
        XCTAssertTrue(snapshot.reviewPlatforms.isEmpty)
    }

    /// The extension's categorizer only looked at `platformVersions`, so a
    /// phasing version behind a newer prepared one disappeared from the widget.
    func testAppleOnlyStoreKeepsAStillPhasingVersionTheExtensionUsedToMiss() async throws {
        try await save(AppModel(
            id: "1", name: "Trailhead", bundleId: "com.trailhead", platform: "IOS", accountId: account.id,
            appStoreState: .prepareForSubmission, versionString: "4.3.0",
            platformVersions: [AppPlatformVersion(platform: "IOS", appStoreState: .prepareForSubmission, versionString: "4.3.0", id: "v-new")],
            awaitingVersions: [AppPlatformVersion(platform: "IOS", appStoreState: .readyForSale, versionString: "4.2.0", id: "v-live")]
        ))
        let phased = PhasedReleaseModel(id: "p", state: .active, startDate: Date(), totalPauseDuration: 0, currentDayNumber: 3)
        try await storage.save(phased, id: "phased.v-live")

        let snapshot = try await snapshot()

        XCTAssertEqual(snapshot.awaitingRelease.map(\.versionText), ["4.2.0"])
        XCTAssertEqual(snapshot.awaitingRelease.first?.progress, .phased(day: 3, total: 7, paused: false))
    }

    /// The extension also listed apps of deleted accounts and the same app once
    /// per registration of its team.
    func testAppleOnlyStoreDropsOrphansAndDuplicateRegistrations() async throws {
        let twin = AccountModel(id: "asc-twin", name: "ASC again", providerType: .apple)
        try await storage.save(twin, id: twin.id)
        for accountId in [account.id, twin.id] {
            try await save(AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", platform: "IOS", accountId: accountId,
                                    appStoreState: .waitingForReview, versionString: "3.1.0"))
        }
        try await save(AppModel(id: "9", name: "Orphan", bundleId: "com.orphan", platform: "IOS", accountId: "gone",
                                appStoreState: .waitingForReview, versionString: "1.0"))

        let snapshot = try await snapshot()

        XCTAssertEqual(snapshot.inReview.map(\.name), ["Pulse"])
        XCTAssertEqual(snapshot.inReviewCount, 1)
    }

    func testCountsKeepTheFullListWhenRowsAreCapped() async throws {
        for index in 0..<15 {
            try await save(AppModel(id: "\(index)", name: "App \(index)", bundleId: "com.app\(index)", platform: "IOS",
                                    accountId: account.id, appStoreState: .waitingForReview, versionString: "1.0"))
        }

        let snapshot = try await snapshot()

        XCTAssertEqual(snapshot.inReview.count, WidgetDashboardSnapshotWriter.maxRows)
        XCTAssertEqual(snapshot.inReviewCount, 15)
    }

    // MARK: - Mixed stores

    func testGooglePlayRowsAndReviewsReachTheSnapshot() async throws {
        let play = AccountModel(id: "play", name: "Play", providerType: .googlePlay)
        try await storage.save(play, id: play.id)
        let item = GooglePlayAppItem(id: "com.t", packageName: "com.t", title: "Trailhead", isManuallyAdded: false, iconUrl: "https://play/icon")
        try await storage.save([item], id: GooglePlayAppItem.cacheKey(accountId: play.id))
        let summaries = GooglePlayReleaseSummariesCache(accountId: play.id, packageName: "com.t", summaries: [
            GooglePlayReleaseSummaryModel(track: "production", name: "5.2.0 (5206)", lifecycleState: .notApproved, versionCodes: ["5206"])
        ], fetchedAt: nil)
        try await storage.save(summaries, id: summaries.cacheKey)
        var review = CustomerReviewModel(id: "com.t/r1", rating: 2, body: "Crashes", createdDate: Date())
        review.appId = "com.t"
        try await storage.save(review, id: CustomerReviewModel.storageId(appId: "com.t", reviewId: review.id))

        let snapshot = try await snapshot()

        XCTAssertEqual(snapshot.inReview.map(\.platform), [.android])
        // Same localized format as `GooglePlayTrackStatusLine.text`, so it holds in any locale.
        let expectedStatus = String(localized: "\(GooglePlayTrackKind(track: "production").displayName) · \(GooglePlayReleaseLifecycleState.notApproved.displayName)")
        XCTAssertEqual(snapshot.inReview.first?.statusText, expectedStatus)
        XCTAssertEqual(snapshot.inReview.first?.iconUrl, "https://play/icon")
        XCTAssertEqual(snapshot.recentReviews.first?.deepLink,
                       DeepLink.review(accountId: play.id, appId: "com.t", reviewId: "com.t/r1").url.absoluteString)
        XCTAssertEqual(snapshot.reviewPlatforms, [.android])
    }
}
