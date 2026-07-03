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
}
