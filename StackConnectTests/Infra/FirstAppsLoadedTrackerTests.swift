import XCTest
@testable import StackConnect

@MainActor
final class FirstAppsLoadedTrackerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var analytics: MockAnalyticsTracker!
    private var sut: FirstAppsLoadedTracker!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "FirstAppsLoadedTrackerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        analytics = MockAnalyticsTracker()
        sut = FirstAppsLoadedTracker(defaults: defaults, analytics: analytics)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        analytics = nil
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - One shot

    func testFirstNonEmptyListSendsTheEventWithCountAndKind() async {
        await sut.recordAppsLoaded(count: 4, provider: .googlePlay, on: .home)

        XCTAssertEqual(analytics.actions(of: .firstAppsLoaded), [
            .action(.firstAppsLoaded, on: .home, parameters: [
                AnalyticsParameterKey.count: .int(4),
                AnalyticsParameterKey.kind: .string("googlePlay")
            ])
        ])
        XCTAssertTrue(sut.hasReached)
    }

    func testIsSentOnlyOnceAcrossLoadsProvidersAndInstances() async {
        await sut.recordAppsLoaded(count: 1, provider: .apple, on: .appList)
        await sut.recordAppsLoaded(count: 9, provider: .apple, on: .home)
        await sut.recordAppsLoaded(count: 2, provider: .firebase, on: .firebaseAppList)

        // A later launch (new instance, same defaults).
        let relaunched = FirstAppsLoadedTracker(defaults: defaults, analytics: analytics)
        await relaunched.recordAppsLoaded(count: 3, provider: .googlePlay, on: .home)

        XCTAssertEqual(analytics.actions(of: .firstAppsLoaded).count, 1)
    }

    func testEmptyListDoesNotCount() async {
        await sut.recordAppsLoaded(count: 0, provider: .apple, on: .home)

        XCTAssertTrue(analytics.actions(of: .firstAppsLoaded).isEmpty)
        XCTAssertFalse(sut.hasReached)
    }

    func testReachedWhileOptedOutIsNeverSentLater() async {
        analytics.setEnabled(false)
        await sut.recordAppsLoaded(count: 2, provider: .apple, on: .home)
        analytics.setEnabled(true)

        await sut.recordAppsLoaded(count: 2, provider: .apple, on: .home)

        XCTAssertTrue(sut.hasReached)
        XCTAssertTrue(analytics.actions(of: .firstAppsLoaded).isEmpty)
    }

    // MARK: - Existing installs

    func testInstallWithCachedAppsIsMarkedWithoutSending() async throws {
        let storage = MockPersistentStorable()
        let app = AppModel(id: "1", name: "App", bundleId: "com.example", platform: "IOS", accountId: "a")
        try await storage.save(app, id: "a.1")

        sut.seedForExistingInstall(storage: storage)
        await sut.recordAppsLoaded(count: 1, provider: .apple, on: .home)

        XCTAssertTrue(sut.hasReached)
        XCTAssertTrue(analytics.actions(of: .firstAppsLoaded).isEmpty)
    }

    func testInstallWithCachedPlayListIsMarkedWithoutSending() async throws {
        let storage = MockPersistentStorable()
        try await storage.save([GooglePlayAppItem(id: "com.example", packageName: "com.example", title: "App", isManuallyAdded: false)], id: GooglePlayAppItem.cacheKey(accountId: "a"))

        sut.seedForExistingInstall(storage: storage)
        await sut.recordAppsLoaded(count: 1, provider: .googlePlay, on: .home)

        XCTAssertTrue(analytics.actions(of: .firstAppsLoaded).isEmpty)
    }

    func testFreshInstallStillSendsAfterTheSeedCheck() async {
        sut.seedForExistingInstall(storage: MockPersistentStorable())
        await sut.recordAppsLoaded(count: 1, provider: .apple, on: .home)

        XCTAssertEqual(analytics.actions(of: .firstAppsLoaded).count, 1)
    }
}
