import XCTest
import StackProtocols
@testable import StackConnect

/// The app-wide "sign in again" prompt of an expired Apple ID session (D5).
@MainActor
final class AppleSessionPromptViewModelTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var center: NotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        center = NotificationCenter()
    }

    override func tearDown() async throws {
        analytics = nil
        center = nil
        try await super.tearDown()
    }

    private func makeSUT(observing: Bool = false) -> AppleSessionPromptViewModel {
        AppleSessionPromptViewModel(analytics: analytics, center: observing ? center : nil)
    }

    private var expiredEvents: [AnalyticsEvent] {
        analytics.trackedEvents.filter { $0.parameters[AnalyticsParameterKey.actionName] == .string(AnalyticsAction.appleSessionExpired.rawValue) }
    }

    func testExpiryShowsThePromptForThatAppleId() {
        let sut = makeSUT()

        sut.sessionDidExpire(appleId: "dev@example.com", isNew: true)

        XCTAssertEqual(sut.uiState.prompt, AppleSessionPrompt(appleId: "dev@example.com"))
        XCTAssertFalse(sut.uiState.isSigningIn)
        XCTAssertEqual(expiredEvents.count, 1)
    }

    func testRepeatedRefusalsAreTrackedOnceAndKeepOnePrompt() {
        let sut = makeSUT()

        sut.sessionDidExpire(appleId: "a@example.com", isNew: true)
        sut.sessionDidExpire(appleId: "a@example.com", isNew: false)
        sut.sessionDidExpire(appleId: "b@example.com", isNew: true)

        XCTAssertEqual(sut.uiState.prompt?.appleId, "a@example.com", "one prompt at a time")
        XCTAssertEqual(expiredEvents.count, 2, "one event per new expiry")
    }

    func testAnOldExpiryStillPromptsAfterRelaunch() {
        let sut = makeSUT()

        sut.sessionDidExpire(appleId: "dev@example.com", isNew: false)

        XCTAssertNotNil(sut.uiState.prompt)
        XCTAssertTrue(expiredEvents.isEmpty)
    }

    func testSignInAgainOpensTheSignIn() {
        let sut = makeSUT()
        sut.sessionDidExpire(appleId: "dev@example.com", isNew: true)

        sut.signInAgain()

        XCTAssertTrue(sut.uiState.isSigningIn)
        XCTAssertEqual(sut.uiState.prompt?.appleId, "dev@example.com")
    }

    func testNotNowSnoozesThatAppleIdForTheLaunch() {
        let sut = makeSUT()
        sut.sessionDidExpire(appleId: "dev@example.com", isNew: true)

        sut.notNow()
        sut.sessionDidExpire(appleId: "dev@example.com", isNew: false)

        XCTAssertNil(sut.uiState.prompt)
        sut.sessionDidExpire(appleId: "other@example.com", isNew: true)
        XCTAssertEqual(sut.uiState.prompt?.appleId, "other@example.com", "other Apple IDs still prompt")
    }

    func testFinishedSignInClosesThePromptAndPromptsAgainOnTheNextExpiry() {
        let sut = makeSUT()
        sut.sessionDidExpire(appleId: "dev@example.com", isNew: true)
        sut.notNow()
        sut.sessionDidExpire(appleId: "x@example.com", isNew: true)
        sut.signInAgain()

        sut.signInFinished()

        XCTAssertEqual(sut.uiState, AppleSessionPromptUiState())
    }

    func testTheStatusStoreNotificationReachesThePrompt() async throws {
        let sut = makeSUT(observing: true)
        let suite = "AppleSessionPromptViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppleSessionStatusStore(defaults: defaults, center: center)

        store.markExpired(appleId: "Dev@Example.com")
        for _ in 0..<50 where sut.uiState.prompt == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(sut.uiState.prompt?.appleId, "dev@example.com")
        XCTAssertEqual(expiredEvents.count, 1)
    }
}
