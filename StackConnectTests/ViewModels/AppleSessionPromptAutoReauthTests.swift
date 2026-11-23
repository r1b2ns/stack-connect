import XCTest
import StackProtocols
@testable import StackConnect

/// The app-wide prompt stays away while the automatic sign-in handles an
/// expiry, and takes over once it falls back to the manual sign-in.
@MainActor
final class AppleSessionPromptAutoReauthTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!
    private var autoReauth: MockAppleSessionAutoReauthenticator!
    private let appleId = "dev@example.com"

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
        autoReauth = MockAppleSessionAutoReauthenticator()
    }

    override func tearDown() async throws {
        analytics = nil
        autoReauth = nil
        try await super.tearDown()
    }

    private func makeSUT() -> AppleSessionPromptViewModel {
        AppleSessionPromptViewModel(analytics: analytics, center: nil, autoReauth: autoReauth)
    }

    func testHandledExpiryShowsNoPromptButIsTracked() {
        autoReauth.handledAppleIds = [appleId]
        let sut = makeSUT()

        sut.sessionDidExpire(appleId: appleId, isNew: true)

        XCTAssertNil(sut.uiState.prompt)
        XCTAssertEqual(analytics.actions(of: .appleSessionExpired).count, 1)
    }

    func testUnhandledExpiryPromptsAsBefore() {
        let sut = makeSUT()

        sut.sessionDidExpire(appleId: appleId, isNew: true)

        XCTAssertEqual(sut.uiState.prompt, AppleSessionPrompt(appleId: appleId))
    }

    func testFailedAttemptsFallBackToThePrompt() {
        let sut = makeSUT()

        autoReauth.send(.finished(appleId: appleId, outcome: .invalidCredentials))

        XCTAssertEqual(sut.uiState.prompt, AppleSessionPrompt(appleId: appleId))

        sut.notNow()
        autoReauth.send(.finished(appleId: appleId, outcome: .failed))
        XCTAssertNil(sut.uiState.prompt, "Not Now still holds for the launch")
    }

    func testACodeLeavesThePromptToTheHomeBanner() {
        let sut = makeSUT()

        autoReauth.send(.finished(appleId: appleId, outcome: .needsCode))

        XCTAssertNil(sut.uiState.prompt, "the Home banner asks for the code: no second sheet")
    }

    func testASuccessClosesALeftoverPrompt() {
        let sut = makeSUT()
        sut.sessionDidExpire(appleId: appleId, isNew: true)

        autoReauth.send(.finished(appleId: appleId, outcome: .done))

        XCTAssertNil(sut.uiState.prompt)
    }

    func testASuccessKeepsASignInInProgress() {
        let sut = makeSUT()
        sut.sessionDidExpire(appleId: appleId, isNew: true)
        sut.signInAgain()

        autoReauth.send(.finished(appleId: appleId, outcome: .done))

        XCTAssertNotNil(sut.uiState.prompt)
        XCTAssertTrue(sut.uiState.isSigningIn)
    }
}
