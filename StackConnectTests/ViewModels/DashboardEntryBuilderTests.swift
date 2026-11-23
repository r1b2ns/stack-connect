import XCTest
@testable import StackConnect

/// Provider-neutral dashboard rows (plan section 6, S2): the H3 mapping table,
/// the rollout bar from the tracks cache, mixed-store grouping and reviews.
@MainActor
final class DashboardEntryBuilderTests: XCTestCase {

    private let playAccount = AccountModel(id: "play-1", name: "Play", providerType: .googlePlay)
    private let appleAccount = AccountModel(id: "asc-1", name: "ASC", providerType: .apple)

    // MARK: - Google Play mapping (H3)

    func testInReviewTakesInReviewNotApprovedAndNotSentForReview() {
        let source = playSource(summaries: [
            summary("production", "5.2.0 (5206)", .notApproved, "5206"),
            summary("beta", "4.3.0-beta2 (4302)", .inReview, "4302"),
            summary("internal", "2.0.0 (201)", .notSentForReview, "201"),
            summary("internal", "2.0.1 (202)", .draft, "202"),
            summary("alpha", "1.0 (10)", .approvedNotPublished, "10"),
            summary("production", "5.1.0 (5106)", .published, "5106")
        ])

        let entries = DashboardEntryBuilder.googlePlayInReview([source])

        XCTAssertEqual(entries.map(\.versionText), ["5.2.0", "4.3.0-beta2", "2.0.0"])
        XCTAssertEqual(entries.map(\.statusColor), [.red, .orange, .gray])
        XCTAssertEqual(entries.first?.statusText, "Production · Not approved")
        XCTAssertEqual(entries.first?.platform, .android)
        XCTAssertEqual(entries.first?.provider, .googlePlay)
        XCTAssertEqual(entries.first?.target, .googlePlay(source.app))
        XCTAssertNil(entries.first?.progress)
    }

    func testAwaitingReleaseTakesApprovedReleasesAndCachedRollouts() {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let source = playSource(
            summaries: [
                summary("production", "2.8.1 (2811)", .approvedNotPublished, "2811"),
                summary("production", "2.7.0 (2704)", .published, "2704"),
                summary("production", "4.2.0 (4210)", .published, "4210")
            ],
            tracks: [GooglePlayTrackModel(track: "production", releases: [
                release("4.2.0 (4210)", .inProgress, "4210", fraction: 0.2),
                release("2.7.0 (2704)", .halted, "2704", fraction: 0.1),
                release("2.6.3 (2631)", .completed, "2631", fraction: nil)
            ])],
            tracksFetchedAt: asOf
        )

        let entries = DashboardEntryBuilder.googlePlayAwaitingRelease([source])

        XCTAssertEqual(entries.map(\.versionText), ["2.8.1", "4.2.0", "2.7.0"])
        XCTAssertEqual(entries[0].statusText, "Production · Approved, not published")
        XCTAssertNil(entries[0].progress)
        XCTAssertEqual(entries[1].statusText, "Production · Rolling out 20%")
        XCTAssertEqual(entries[1].progress, .rollout(fraction: 0.2, halted: false, asOf: asOf))
        XCTAssertEqual(entries[1].statusColor, .blue)
        XCTAssertEqual(entries[2].statusText, "Production · Halted at 10%")
        XCTAssertEqual(entries[2].progress?.isPaused, true)
    }

    func testNoTracksCacheMeansNoRolloutRowAndNoBar() {
        let source = playSource(summaries: [summary("production", "4.2.0 (4210)", .published, "4210")], tracks: nil)

        XCTAssertTrue(DashboardEntryBuilder.googlePlayAwaitingRelease([source]).isEmpty)
    }

    func testCachedRolloutIsDroppedWhenTheSummariesNoLongerListTheRelease() {
        let source = playSource(
            summaries: [summary("production", "4.3.0 (4300)", .published, "4300")],
            tracks: [GooglePlayTrackModel(track: "production", releases: [release("4.2.0 (4210)", .inProgress, "4210", fraction: 0.5)])]
        )

        XCTAssertTrue(DashboardEntryBuilder.googlePlayAwaitingRelease([source]).isEmpty)
    }

    func testSamePackageUnderTwoAccountsIsOneRow() {
        let other = AccountModel(id: "play-2", name: "Play 2", providerType: .googlePlay)
        let summaries = [summary("production", "1.0 (1)", .inReview, "1")]
        let entries = DashboardEntryBuilder.googlePlayInReview([
            playSource(summaries: summaries),
            playSource(account: other, summaries: summaries)
        ])

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.accountId, playAccount.id)
    }

    // MARK: - Mixed stores

    func testGroupsApplePlatformsBeforeAndroid() {
        let apple = DashboardEntryBuilder.appStoreInReview([
            AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", platform: "IOS", accountId: appleAccount.id,
                     appStoreState: .waitingForReview, versionString: "3.1.0", lastModifiedDate: Date()),
            AppModel(id: "2", name: "Orbit", bundleId: "com.orbit", platform: "MAC_OS", accountId: appleAccount.id,
                     appStoreState: .inReview, versionString: "3.0.0")
        ], accounts: [appleAccount.id: appleAccount])
        let play = DashboardEntryBuilder.googlePlayInReview([playSource(summaries: [summary("production", "1.0 (1)", .inReview, "1")])])

        let groups = DashboardEntryBuilder.groupByPlatform(DashboardEntryBuilder.merged(appStore: apple, googlePlay: play))

        XCTAssertEqual(groups.map(\.platform), [.iOS, .macOS, .android])
        XCTAssertEqual(groups.first?.entries.first?.statusText, AppStoreState.waitingForReview.displayName)
        XCTAssertEqual(groups.first?.entries.first?.account, appleAccount)
    }

    func testAppStorePhasedProgressIsDayOfSeven() {
        let app = AppModel(id: "1", name: "Trailhead", bundleId: "com.t", platform: "IOS", accountId: appleAccount.id,
                           appStoreState: .readyForSale, versionString: "4.2.0",
                           awaitingVersions: [AppPlatformVersion(platform: "IOS", appStoreState: .readyForSale, versionString: "4.2.0", id: "v1")])
        let phased = PhasedReleaseModel(id: "p", state: .active, startDate: Date(), totalPauseDuration: 0, currentDayNumber: 3)

        let entries = DashboardEntryBuilder.appStoreAwaitingRelease([app], phasedByVersionId: ["v1": phased], accounts: [:])

        XCTAssertEqual(entries.first?.progress, .phased(day: 3, total: 7, paused: false))
        XCTAssertNil(entries.first?.account)
    }

    // MARK: - Reviews

    func testReviewsMixBothStoresNewestFirstAndDropOrphans() {
        let appleApp = AppModel(id: "123", name: "Pulse", bundleId: "com.pulse", platform: "IOS", accountId: appleAccount.id)
        let reviews = [
            review("a", appId: "123", hoursAgo: 5),
            review("p", appId: "com.northwind.trailhead", hoursAgo: 2),
            review("orphan", appId: "com.unknown", hoursAgo: 1)
        ]

        let rows = DashboardEntryBuilder.reviews(
            reviews,
            appStoreApps: [appleApp],
            googlePlaySources: [playSource(summaries: [])],
            accounts: [appleAccount.id: appleAccount, playAccount.id: playAccount]
        )

        XCTAssertEqual(rows.map(\.review.id), ["p", "a"])
        XCTAssertEqual(rows.map(\.platform), [.android, .iOS])
        XCTAssertEqual(rows.first?.account, playAccount)
        XCTAssertEqual(rows.first?.appName, "Trailhead")
    }

    func testAppStoreReviewOfAnUnknownAccountIsDropped() {
        let appleApp = AppModel(id: "123", name: "Pulse", bundleId: "com.pulse", accountId: "gone")
        let rows = DashboardEntryBuilder.reviews(
            [review("a", appId: "123", hoursAgo: 1)],
            appStoreApps: [appleApp], googlePlaySources: [],
            accounts: [appleAccount.id: appleAccount]
        )
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Loading the Play sources

    func testLoadGooglePlaySourcesKeepsScopeAndRules() async throws {
        let storage = MockPersistentStorable()
        let scoped = AccountModel(id: "play-scoped", name: "Imported", providerType: .googlePlay, rules: .allPermissions,
                                  origin: .imported, appsBundles: ["com.a"])
        let noVersion = AccountModel(id: "play-noversion", name: "No version", providerType: .googlePlay,
                                     rules: AccountRules(apps: AccountPermission.allCases, review: [.view]), origin: .imported)
        for account in [scoped, noVersion] {
            try await storage.save([item("com.a"), item("com.b")], id: GooglePlayAppItem.cacheKey(accountId: account.id))
        }
        let accounts = [scoped.id: scoped, noVersion.id: noVersion]

        let status = await HomeWidgetDataLoader.loadGooglePlaySources(storage: storage, accounts: accounts, requiring: .version, includesReleaseCaches: true, featureFlags: .googlePlayOn)
        let reviews = await HomeWidgetDataLoader.loadGooglePlaySources(storage: storage, accounts: accounts, requiring: .review, includesReleaseCaches: false, featureFlags: .googlePlayOn)

        XCTAssertEqual(status.map(\.app.packageName), ["com.a"])
        XCTAssertEqual(Set(reviews.map { "\($0.account.id)/\($0.app.packageName)" }),
                       ["play-scoped/com.a", "play-noversion/com.a", "play-noversion/com.b"])
    }

    // MARK: - Helpers

    private func item(_ packageName: String, title: String? = nil) -> GooglePlayAppItem {
        GooglePlayAppItem(id: packageName, packageName: packageName, title: title, isManuallyAdded: false)
    }

    private func playSource(
        account: AccountModel? = nil,
        summaries: [GooglePlayReleaseSummaryModel],
        tracks: [GooglePlayTrackModel]? = nil,
        tracksFetchedAt: Date? = nil
    ) -> GooglePlayDashboardSource {
        let account = account ?? playAccount
        let packageName = "com.northwind.trailhead"
        return GooglePlayDashboardSource(
            account: account,
            app: item(packageName, title: "Trailhead"),
            summaries: GooglePlayReleaseSummariesCache(accountId: account.id, packageName: packageName, summaries: summaries, fetchedAt: nil),
            tracks: tracks.map { GooglePlayTracksCache(accountId: account.id, packageName: packageName, tracks: $0, fetchedAt: tracksFetchedAt) }
        )
    }

    private func summary(_ track: String, _ name: String?, _ state: GooglePlayReleaseLifecycleState, _ code: String) -> GooglePlayReleaseSummaryModel {
        GooglePlayReleaseSummaryModel(track: track, name: name, lifecycleState: state, versionCodes: [code])
    }

    private func release(_ name: String, _ status: GooglePlayReleaseStatus, _ code: String, fraction: Double?) -> GooglePlayReleaseModel {
        GooglePlayReleaseModel(name: name, status: status, versionCodes: [code], userFraction: fraction, releaseNotes: [], inAppUpdatePriority: nil)
    }

    private func review(_ id: String, appId: String, hoursAgo: Double) -> CustomerReviewModel {
        var review = CustomerReviewModel(id: id, rating: 4, body: "Body", createdDate: Date().addingTimeInterval(-hoursAgo * 3600))
        review.appId = appId
        return review
    }
}
