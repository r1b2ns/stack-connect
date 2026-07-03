import XCTest
@testable import StackConnect

final class AppStatusCategorizerTests: XCTestCase {

    func testCategorizeGroupsReviewStates() {
        let apps: [AppModel] = [
            makeApp(id: "1", state: .waitingForReview),
            makeApp(id: "2", state: .inReview),
            makeApp(id: "3", state: .rejected),
            makeApp(id: "4", state: .readyForSale)
        ]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: [:])

        XCTAssertEqual(Set(result.inReview.map(\.id)), ["1", "2", "3"])
        XCTAssertTrue(result.awaitingRelease.isEmpty)
    }

    func testPendingDeveloperReleaseIsAwaitingRelease() {
        let apps = [makeApp(id: "1", state: .pendingDeveloperRelease)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: [:])

        XCTAssertEqual(result.awaitingRelease.map(\.id), ["1"])
        XCTAssertTrue(result.inReview.isEmpty)
    }

    func testReadyForSaleWithActivePhasedIsAwaitingRelease() {
        let apps = [makeApp(id: "1", state: .readyForSale)]
        let phased = ["1": PhasedReleaseModel(id: "phased.1", state: .active)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: phased)

        XCTAssertEqual(result.awaitingRelease.map(\.id), ["1"])
    }

    func testReadyForSaleWithPausedPhasedIsAwaitingRelease() {
        let apps = [makeApp(id: "1", state: .readyForSale)]
        let phased = ["1": PhasedReleaseModel(id: "phased.1", state: .paused)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: phased)

        XCTAssertEqual(result.awaitingRelease.map(\.id), ["1"])
    }

    func testReadyForSaleWithCompletePhasedIsIgnored() {
        let apps = [makeApp(id: "1", state: .readyForSale)]
        let phased = ["1": PhasedReleaseModel(id: "phased.1", state: .complete)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: phased)

        XCTAssertTrue(result.awaitingRelease.isEmpty)
        XCTAssertTrue(result.inReview.isEmpty)
    }

    func testAppsWithoutStateAreIgnored() {
        let apps = [makeApp(id: "1", state: nil)]

        let result = AppStatusCategorizer.categorize(apps, phasedByAppId: [:])

        XCTAssertTrue(result.inReview.isEmpty)
        XCTAssertTrue(result.awaitingRelease.isEmpty)
    }

    // MARK: - awaitingReleaseEntries (per-platform expansion)

    /// The reported bug: the overall-latest/primary version is iOS in a
    /// non-awaiting state, while a tvOS version is `readyForSale` with an active
    /// phased release. The tvOS entry must appear in the awaiting bucket.
    func testAwaitingEntriesSurfacesPhasedTvOSWhilePrimaryIsIOS() {
        let app = makeMultiPlatformApp(
            id: "1",
            primaryState: .prepareForSubmission,
            primaryPlatform: .ios,
            versions: [
                platform(.ios, .prepareForSubmission, versionId: "v-ios"),
                platform(.tvOs, .readyForSale, versionId: "v-tv")
            ]
        )
        let phased = ["v-tv": PhasedReleaseModel(id: "phased.v-tv", state: .active)]

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.platform, AppPlatform.tvOs.rawValue)
        XCTAssertEqual(entries.first?.appStoreState, .readyForSale)
        XCTAssertEqual(entries.first?.versionString, "1.0-TV_OS")
    }

    /// A tvOS version in `pendingDeveloperRelease` awaits regardless of phased,
    /// while the primary iOS version does not.
    func testAwaitingEntriesSurfacesPendingDeveloperReleaseTvOS() {
        let app = makeMultiPlatformApp(
            id: "1",
            primaryState: .readyForSale,
            primaryPlatform: .ios,
            versions: [
                platform(.ios, .readyForSale, versionId: "v-ios"),
                platform(.tvOs, .pendingDeveloperRelease, versionId: "v-tv")
            ]
        )
        // iOS is readyForSale but has no phased → not awaiting. Only tvOS awaits.
        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: [:])

        XCTAssertEqual(entries.map(\.platform), [AppPlatform.tvOs.rawValue])
        XCTAssertEqual(entries.first?.appStoreState, .pendingDeveloperRelease)
    }

    /// A `readyForSale` version whose phased release is `complete` is excluded.
    func testAwaitingEntriesExcludesCompletePhasedTvOS() {
        let app = makeMultiPlatformApp(
            id: "1",
            primaryState: .prepareForSubmission,
            primaryPlatform: .ios,
            versions: [
                platform(.ios, .prepareForSubmission, versionId: "v-ios"),
                platform(.tvOs, .readyForSale, versionId: "v-tv")
            ]
        )
        let phased = ["v-tv": PhasedReleaseModel(id: "phased.v-tv", state: .complete)]

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)

        XCTAssertTrue(entries.isEmpty)
    }

    /// Two platforms both phasing yield two independent awaiting entries.
    func testAwaitingEntriesEmitsOnePerPhasingPlatform() {
        let app = makeMultiPlatformApp(
            id: "1",
            primaryState: .readyForSale,
            primaryPlatform: .ios,
            versions: [
                platform(.ios, .readyForSale, versionId: "v-ios"),
                platform(.tvOs, .readyForSale, versionId: "v-tv")
            ]
        )
        let phased = [
            "v-ios": PhasedReleaseModel(id: "phased.v-ios", state: .active),
            "v-tv": PhasedReleaseModel(id: "phased.v-tv", state: .paused)
        ]

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)

        XCTAssertEqual(Set(entries.compactMap(\.platform)), [AppPlatform.ios.rawValue, AppPlatform.tvOs.rawValue])
    }

    /// A `readyForSale` version with no phased release is not awaiting.
    func testAwaitingEntriesExcludesReadyForSaleWithoutPhased() {
        let app = makeMultiPlatformApp(
            id: "1",
            primaryState: .readyForSale,
            primaryPlatform: .ios,
            versions: [
                platform(.ios, .readyForSale, versionId: "v-ios"),
                platform(.tvOs, .readyForSale, versionId: "v-tv")
            ]
        )

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: [:])

        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - awaitingReleaseEntries fallback (single-platform / no platformVersions)

    /// Single-platform apps (empty `platformVersions`) still behave as before:
    /// pendingDeveloperRelease on the primary state awaits, keyed by app id.
    func testAwaitingEntriesFallbackPendingDeveloperRelease() {
        let app = makeApp(id: "1", state: .pendingDeveloperRelease)

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: [:])

        XCTAssertEqual(entries.map(\.id), ["1"])
    }

    /// Fallback path: a single-platform `readyForSale` app resolves its phased
    /// release under the app id key.
    func testAwaitingEntriesFallbackReadyForSaleWithPhasedByAppId() {
        let app = makeApp(id: "1", state: .readyForSale)
        let phased = ["1": PhasedReleaseModel(id: "phased.1", state: .active)]

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)

        XCTAssertEqual(entries.map(\.id), ["1"])
    }

    /// Fallback path: `readyForSale` with no phased release is not awaiting.
    func testAwaitingEntriesFallbackReadyForSaleWithoutPhasedIsIgnored() {
        let app = makeApp(id: "1", state: .readyForSale)

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: [:])

        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - awaitingVersions (phasing version behind a newer prepared version)

    /// The reported bug: the app ships iOS (3.1.0 in `prepareForSubmission`) and
    /// tvOS (3.1.0 `readyForSale`, phasing). The still-phasing tvOS version must
    /// appear in "Awaiting Release", and the entry must keep the app's full
    /// platform list so App Detail's header shows every platform (the regression
    /// showed only the awaiting platform).
    func testAwaitingEntriesSurfacesPhasingVersionBehindNewerPreparedVersion() {
        let app = makeAppWithAwaiting(
            id: "1",
            primaryState: .prepareForSubmission,
            platformVersions: [
                platform(.ios, .prepareForSubmission, versionId: "v-ios-310"),
                platform(.tvOs, .readyForSale, versionId: "v-tv-310")
            ],
            awaitingVersions: [platform(.tvOs, .readyForSale, versionId: "v-tv-310")]
        )
        let phased = ["v-tv-310": PhasedReleaseModel(id: "phased.v-tv", state: .active)]

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)

        XCTAssertEqual(entries.count, 1)
        let entry = entries.first
        XCTAssertEqual(entry?.appStoreState, .readyForSale)
        XCTAssertEqual(entry?.platform, AppPlatform.tvOs.rawValue)
        // Regression guard: the entry preserves the app's full platform list so
        // App Detail's header shows iOS AND tvOS, not just the awaiting platform.
        XCTAssertEqual(
            Set(entry?.platformVersions?.compactMap(\.platform) ?? []),
            [AppPlatform.ios.rawValue, AppPlatform.tvOs.rawValue]
        )
        // The widget still resolves the exact phased release for this entry.
        XCTAssertEqual(HomeWidgetDataLoader.phasedRelease(for: entry!, in: phased)?.state, .active)
    }

    /// Same as above but the rollout is paused — it must still appear.
    func testAwaitingEntriesSurfacesPausedPhasingVersionBehindNewerPreparedVersion() {
        let app = makeAppWithAwaiting(
            id: "1",
            primaryState: .prepareForSubmission,
            platformVersions: [platform(.ios, .prepareForSubmission, versionId: "v-310")],
            awaitingVersions: [platform(.ios, .readyForSale, versionId: "v-303")]
        )
        let phased = ["v-303": PhasedReleaseModel(id: "phased.v-303", state: .paused)]

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.appStoreState, .readyForSale)
    }

    /// The same platform can expose both a newer `pendingDeveloperRelease` version
    /// and an older still-phasing `readyForSale` version — both must appear, and
    /// the widget must resolve each to its own phased release.
    func testAwaitingEntriesEmitsBothPendingAndPhasingForSamePlatform() {
        let pending = AppPlatformVersion(platform: AppPlatform.ios.rawValue, appStoreState: .pendingDeveloperRelease, versionString: "3.1.1", id: "v-311")
        let phasing = AppPlatformVersion(platform: AppPlatform.ios.rawValue, appStoreState: .readyForSale, versionString: "3.0.3", id: "v-303")
        let app = makeAppWithAwaiting(
            id: "1",
            primaryState: .pendingDeveloperRelease,
            platformVersions: [pending],
            awaitingVersions: [pending, phasing]
        )
        let phased = ["v-303": PhasedReleaseModel(id: "phased.v-303", state: .active)]

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.compactMap(\.versionString)), ["3.1.1", "3.0.3"])

        // The widget resolves each entry to its own phased release by
        // platform + version string: the phasing 3.0.3 gets the active rollout,
        // the pending 3.1.1 has none.
        let phasingEntry = entries.first { $0.versionString == "3.0.3" }
        let pendingEntry = entries.first { $0.versionString == "3.1.1" }
        XCTAssertEqual(HomeWidgetDataLoader.phasedRelease(for: phasingEntry!, in: phased)?.state, .active)
        XCTAssertNil(HomeWidgetDataLoader.phasedRelease(for: pendingEntry!, in: phased))
    }

    /// A non-nil (even empty) `awaitingVersions` is authoritative: it short-circuits
    /// the legacy `platformVersions` fallback.
    func testEmptyAwaitingVersionsSuppressesLegacyPlatformVersionsFallback() {
        let app = makeAppWithAwaiting(
            id: "1",
            primaryState: .readyForSale,
            platformVersions: [platform(.ios, .readyForSale, versionId: "v-1")],
            awaitingVersions: []
        )
        let phased = ["v-1": PhasedReleaseModel(id: "phased.v-1", state: .active)]

        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)

        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - loadPhasedReleases integration

    /// Regression: `loadPhasedReleases` must look up phased releases for versions
    /// in `awaitingVersions` (a still-phasing readyForSale version behind a newer
    /// prepared one), not only `platformVersions` — otherwise the app never
    /// surfaces in Awaiting Release even though its rollout was stored.
    func testLoadPhasedReleasesIncludesAwaitingVersionsBehindNewerVersion() async throws {
        let storage = MockPersistentStorable()
        try await storage.save(
            PhasedReleaseModel(id: "p", state: .active, currentDayNumber: 3),
            id: "phased.v-303"
        )
        let app = makeAppWithAwaiting(
            id: "1",
            primaryState: .prepareForSubmission,
            platformVersions: [platform(.ios, .prepareForSubmission, versionId: "v-310")],
            awaitingVersions: [platform(.ios, .readyForSale, versionId: "v-303")]
        )

        let phased = await HomeWidgetDataLoader.loadPhasedReleases(for: [app], storage: storage)

        // The phasing version's rollout is loaded even though it isn't in platformVersions.
        XCTAssertEqual(phased["v-303"]?.state, .active)

        // End-to-end: the app now surfaces in Awaiting Release.
        let entries = AppStatusCategorizer.awaitingReleaseEntries([app], phasedByVersionId: phased)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.appStoreState, .readyForSale)
    }

    // MARK: - Helpers

    private func makeApp(id: String, state: AppStoreState?) -> AppModel {
        AppModel(
            id: id,
            name: "App \(id)",
            bundleId: "com.test.\(id)",
            accountId: "acc",
            appStoreState: state
        )
    }

    private func platform(
        _ platform: AppPlatform,
        _ state: AppStoreState,
        versionId: String
    ) -> AppPlatformVersion {
        AppPlatformVersion(
            platform: platform.rawValue,
            appStoreState: state,
            versionString: "1.0-\(platform.rawValue)",
            id: versionId
        )
    }

    private func makeMultiPlatformApp(
        id: String,
        primaryState: AppStoreState,
        primaryPlatform: AppPlatform,
        versions: [AppPlatformVersion]
    ) -> AppModel {
        AppModel(
            id: id,
            name: "App \(id)",
            bundleId: "com.test.\(id)",
            platform: primaryPlatform.rawValue,
            accountId: "acc",
            appStoreState: primaryState,
            versionString: "1.0-primary",
            platformVersions: versions
        )
    }

    private func makeAppWithAwaiting(
        id: String,
        primaryState: AppStoreState,
        primaryPlatform: AppPlatform = .ios,
        platformVersions: [AppPlatformVersion],
        awaitingVersions: [AppPlatformVersion]
    ) -> AppModel {
        AppModel(
            id: id,
            name: "App \(id)",
            bundleId: "com.test.\(id)",
            platform: primaryPlatform.rawValue,
            accountId: "acc",
            appStoreState: primaryState,
            versionString: "1.0-primary",
            platformVersions: platformVersions,
            awaitingVersions: awaitingVersions
        )
    }
}
