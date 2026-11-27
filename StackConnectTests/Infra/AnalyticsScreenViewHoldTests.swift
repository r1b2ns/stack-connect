import XCTest
import StackProtocols
@testable import StackConnect

/// `screen_view` events tracked before the app is active are held and sent
/// once it becomes active (GA4 "(not set)" screen name at cold launch).
@MainActor
final class AnalyticsScreenViewHoldTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var provider: MockAnalyticsProvider!
    private var activity: MockAppActivityMonitor!
    private var sut: AnalyticsService!

    override func setUp() async throws {
        suiteName = "AnalyticsScreenViewHoldTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = AppSettings(defaults: defaults)
        provider = MockAnalyticsProvider()
        activity = MockAppActivityMonitor(isActive: false)
        sut = AnalyticsService(providers: [provider], settings: settings, bundle: Bundle(for: Self.self), appActivity: activity)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        activity = nil
        provider = nil
        settings = nil
        defaults = nil
    }

    private var sentScreenNames: [String] {
        provider.sentEvents
            .filter { $0.name == "screen_view" }
            .compactMap { $0.parameters["screen_name"]?.stringValue }
    }

    func testObservesActivationOnce() {
        XCTAssertEqual(activity.observeCount, 1)
    }

    func testScreenViewBeforeActiveIsHeldThenSentWithItsScreenName() throws {
        sut.track(.screenView(.home))

        XCTAssertTrue(provider.sentEvents.isEmpty, "Nothing reaches the SDK before the app is active")
        XCTAssertEqual(sut.heldScreenViews.count, 1)

        activity.becomeActive()

        XCTAssertEqual(provider.sentEventNames, ["screen_view"])
        let event = try XCTUnwrap(provider.sentEvents.first)
        XCTAssertEqual(event.parameters["screen_name"], .string("home"))
        XCTAssertNotNil(event.parameters["build_number"], "Standard parameters are still attached")
        XCTAssertTrue(sut.heldScreenViews.isEmpty)
    }

    func testHeldScreenViewsKeepTheirOrderAndDedupeConsecutiveRepeats() {
        sut.track(.screenView(.home))
        sut.track(.screenView(.home))
        sut.track(.screenView(.settings))
        sut.track(.screenView(.home))

        activity.becomeActive()

        XCTAssertEqual(sentScreenNames, ["home", "settings", "home"])
    }

    func testNonScreenEventsAreNotDelayed() {
        sut.track(.screenView(.home))
        sut.track(.buttonTap(.license, on: .settings))

        XCTAssertEqual(provider.sentEventNames, ["button_tap"])

        activity.becomeActive()

        XCTAssertEqual(provider.sentEventNames, ["button_tap", "screen_view"])
    }

    func testScreenViewWhileActiveIsSentRightAway() {
        activity.becomeActive()

        sut.track(.screenView(.home))

        XCTAssertEqual(sentScreenNames, ["home"])
        XCTAssertTrue(sut.heldScreenViews.isEmpty)
    }

    func testScreenViewTrackedAfterActiveButBeforeTheHeldOnesWereSentWaitsBehindThem() {
        sut.track(.screenView(.home))
        // `applicationState` is already `.active`, the deferred handler has not run yet.
        activity.isActive = true
        sut.track(.screenView(.settings))

        XCTAssertTrue(provider.sentEvents.isEmpty)

        sut.dispatchPendingScreenViews()

        XCTAssertEqual(sentScreenNames, ["home", "settings"])
    }

    func testScreenViewAfterReturningFromBackgroundIsHeldAgain() {
        activity.becomeActive()
        sut.track(.screenView(.home))
        activity.resignActive()

        sut.track(.screenView(.settings))
        XCTAssertEqual(sentScreenNames, ["home"])

        activity.becomeActive()
        XCTAssertEqual(sentScreenNames, ["home", "settings"])
    }

    func testBecomingActiveWithNothingHeldSendsNothing() {
        activity.becomeActive()

        XCTAssertTrue(provider.sentEvents.isEmpty)
    }

    func testHeldScreenViewsAreSentOnlyOnce() {
        sut.track(.screenView(.home))

        activity.becomeActive()
        activity.becomeActive()

        XCTAssertEqual(sentScreenNames, ["home"])
    }

    func testOptOutDropsHeldScreenViews() {
        sut.track(.screenView(.home))
        sut.setEnabled(false)

        activity.becomeActive()

        XCTAssertEqual(provider.sentEventNames, ["analytics_disabled"])
    }

    func testScreenViewWhileOptedOutIsNeverHeld() {
        sut.setEnabled(false)
        sut.track(.screenView(.home))

        XCTAssertTrue(sut.heldScreenViews.isEmpty)
    }

    func testWithoutActivitySourceNothingIsHeld() {
        let service = AnalyticsService(providers: [provider], settings: settings)

        service.track(.screenView(.home))

        XCTAssertEqual(sentScreenNames, ["home"])
    }

    // MARK: - Queue

    func testQueueDedupesOnlyConsecutiveIdenticalEvents() {
        var queue = PendingScreenViewQueue()
        queue.enqueue(.screenView(.home))
        queue.enqueue(.screenView(.home))
        queue.enqueue(.screenView(.settings))
        queue.enqueue(.screenView(.home))

        XCTAssertEqual(queue.events, [.screenView(.home), .screenView(.settings), .screenView(.home)])
    }

    func testQueueDrainEmptiesIt() {
        var queue = PendingScreenViewQueue()
        queue.enqueue(.screenView(.home))

        XCTAssertEqual(queue.drain(), [.screenView(.home)])
        XCTAssertTrue(queue.isEmpty)
    }
}
