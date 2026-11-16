import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics coverage for the build list / detail ViewModels. They build their
/// `AppleAccountConnection` inline, so only the no-credentials paths run offline.
@MainActor
final class BuildsViewModelsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private let account = AccountModel(name: "Team", providerType: .apple)
    private let build = BuildModel(id: "build-1", version: "1", platform: "IOS")

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - PlatformBuilds

    func testPlatformBuildsLoadTracksNothingAndRefreshTracksFailure() async {
        let sut = PlatformBuildsViewModel(appId: "app-1", platform: "IOS", account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .platformBuilds, result: .failure)])
    }

    func testPlatformBuildsExpireTracksTapAndFailure() async {
        let sut = PlatformBuildsViewModel(appId: "app-1", platform: "IOS", account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.expireBuild(build)

        XCTAssertEqual(analytics.taps(of: .confirmExpire), [.buttonTap(.confirmExpire, on: .platformBuilds)])
        XCTAssertEqual(analytics.actions(of: .expireBuild), [.action(.expireBuild, on: .platformBuilds, result: .failure)])
    }

    // MARK: - AvailableBuilds

    func testAvailableBuildsLoadTracksNothingAndRefreshTracksFailure() async {
        let sut = AvailableBuildsForPlatformViewModel(
            appId: "app-1",
            platform: "IOS",
            account: account,
            assignedBuildIds: [],
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .availableBuilds, result: .failure)])
    }

    // MARK: - BuildDetail

    func testBuildDetailLoadTracksNothingAndRefreshTracksFailure() async {
        let sut = BuildDetailViewModel(build: build, appId: "app-1", account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .buildDetail, result: .failure)])
    }

    func testBuildDetailExpireTracksTapAndFailure() async {
        let sut = BuildDetailViewModel(build: build, appId: "app-1", account: account, keychain: MockKeyStorable(), analytics: analytics)

        await sut.expireBuild()

        XCTAssertEqual(analytics.taps(of: .confirmExpire), [.buttonTap(.confirmExpire, on: .buildDetail)])
        XCTAssertEqual(analytics.actions(of: .expireBuild), [.action(.expireBuild, on: .buildDetail, result: .failure)])
    }
}
