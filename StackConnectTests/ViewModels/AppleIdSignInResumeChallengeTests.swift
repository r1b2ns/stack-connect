import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// Signing in again from the code step an automatic sign-in left
/// (`AppleSessionPendingChallenge`): the password isn't asked, a stale
/// challenge falls back to a new sign-in with the saved password.
@MainActor
final class AppleIdSignInResumeChallengeTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var status: MockAppleSessionStatus!
    private var autoReauth: MockAppleSessionAutoReauthenticator!
    /// The challenge's core sign-in (Apple already sent its code).
    private var pendingFlow: MockAppleIdSignIn!
    /// What `makeSignIn` builds for a new sign-in.
    private var freshFlow: MockAppleIdSignIn!
    private var signInsMade = 0

    private let appleId = "dev@example.com"
    private let blob = Data("new-session".utf8)
    private var passwordKey: String { "applePassword.\(appleId)" }

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        status = MockAppleSessionStatus()
        autoReauth = MockAppleSessionAutoReauthenticator()
        pendingFlow = MockAppleIdSignIn()
        pendingFlow.finishResult = .success(blob)
        freshFlow = MockAppleIdSignIn()
        signInsMade = 0
        keychain.set("saved", forKey: passwordKey)
        status.markExpired(appleId: appleId)
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        analytics = nil
        status = nil
        autoReauth = nil
        pendingFlow = nil
        freshFlow = nil
        try await super.tearDown()
    }

    private func makeSUT(_ mode: AppleIdSignInMode? = nil) -> AppleIdSignInViewModel {
        AppleIdSignInViewModel(
            mode: mode ?? .signInAgain(appleId: appleId),
            storage: storage,
            keychain: keychain,
            sessionStatus: status,
            roleResolver: MockAppleSessionRoleResolver(),
            analytics: analytics,
            autoReauth: autoReauth,
            makeSignIn: { [unowned self] _ in
                self.signInsMade += 1
                return self.freshFlow
            }
        )
    }

    private func leavePendingChallenge(delivery: AppleCodeDelivery = .trustedDevices) {
        autoReauth.challenges[appleId] = .fixture(appleId: appleId, flow: pendingFlow, delivery: delivery)
        autoReauth.states[appleId] = .awaitingCode(AppleSessionCodeDestination(delivery))
    }

    private var needsCode: AppleSignInStep {
        .needsCode(methods: [.trustedDevice], phones: [.fixture], codeLength: 6, delivery: .trustedDevices)
    }

    // MARK: - Resume

    func testResumesAtTheCodeStepWithoutAskingThePassword() async {
        leavePendingChallenge()

        let sut = makeSUT()
        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertTrue(sut.uiState.usesSavedPassword)
        XCTAssertEqual(sut.uiState.codeMethod, .trustedDevice)
        XCTAssertEqual(sut.uiState.codeLength, 6)
        XCTAssertEqual(sut.uiState.notice, String(localized: "Enter the code shown on your Apple devices."))
        XCTAssertTrue(pendingFlow.starts.isEmpty, "no new sign-in: Apple already sent the code")
        XCTAssertEqual(signInsMade, 0)
    }

    func testResumedCodeRenewsTheSession() async {
        leavePendingChallenge()
        pendingFlow.submitResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()

        await sut.updateCode("123456")

        XCTAssertEqual(pendingFlow.submittedCodes.map(\.code), ["123456"])
        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertEqual(keychain.data(forKey: "appleSession.\(appleId)"), blob)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "the saved password stays saved")
        XCTAssertEqual(status.markedValid, [appleId])
        XCTAssertEqual(autoReauth.discarded, [appleId], "the challenge is used up")
    }

    func testResumedChallengeKeepsTheSavedPassword() async {
        leavePendingChallenge()
        pendingFlow.submitResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()
        XCTAssertTrue(sut.uiState.savesPassword, "a password is saved: on, though the toggle isn't shown")

        await sut.updateCode("123456")

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "never removed by the off default")
        XCTAssertEqual(keychain.writtenKeys.filter { $0 == passwordKey }.count, 2, "written again once signed in: refreshed")
    }

    func testResumedTextMessageCodeIsShown() {
        leavePendingChallenge(delivery: .phone(phoneId: AppleTrustedPhone.fixture.id))

        let sut = makeSUT()

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertEqual(sut.uiState.codeMethod, .phone(phoneId: AppleTrustedPhone.fixture.id))
        XCTAssertEqual(
            sut.uiState.notice,
            String(localized: "Enter the code sent to \(AppleTrustedPhone.fixture.maskedNumber).",
                   comment: "Apple ID sign-in, code screen. The placeholder is the masked trusted phone number, e.g. +49 •••• •••••85.")
        )
    }

    func testWithoutAPendingChallengeTheSavedPasswordSignsIn() async {
        let sut = makeSUT()
        freshFlow.startResults = [.success(needsCode)]

        XCTAssertEqual(sut.uiState.step, .credentials)
        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertEqual(freshFlow.starts, [.init(email: appleId, password: "saved")], "today's behaviour: a new code is sent")
        XCTAssertEqual(sut.uiState.step, .code)
    }

    func testAddAccountNeverResumesAChallenge() {
        leavePendingChallenge()

        let sut = makeSUT(.addAccounts)

        XCTAssertEqual(sut.uiState.step, .credentials)
    }

    // MARK: - Stale or abandoned challenge

    func testStaleChallengeSignsInAgainWithTheSavedPassword() async {
        leavePendingChallenge()
        pendingFlow.submitResults = [.failure(StackError.Auth(message: "the sign-in expired"))]
        freshFlow.startResults = [.success(needsCode)]
        let sut = makeSUT()

        await sut.updateCode("123456")

        XCTAssertEqual(autoReauth.discarded, [appleId])
        XCTAssertEqual(freshFlow.starts, [.init(email: appleId, password: "saved")], "a new code is sent")
        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertNil(sut.uiState.errorMessage)
        XCTAssertFalse(sut.uiState.isWorking)
    }

    func testStaleChallengeWithoutASavedPasswordAsksForIt() async {
        leavePendingChallenge()
        pendingFlow.submitResults = [.failure(StackError.Auth(message: "the sign-in expired"))]
        let sut = makeSUT()
        keychain.removeObject(forKey: passwordKey)

        await sut.updateCode("123456")

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertFalse(sut.uiState.usesSavedPassword)
        XCTAssertTrue(freshFlow.starts.isEmpty)
    }

    func testWrongCodeKeepsTheResumedChallenge() async {
        leavePendingChallenge()
        pendingFlow.submitResults = [.failure(StackError.InvalidCredentials(message: "wrong code"))]
        let sut = makeSUT()

        await sut.updateCode("000000")

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertEqual(sut.uiState.codeError, String(localized: "That code isn't right. Check it and try again."))
        XCTAssertTrue(autoReauth.discarded.isEmpty)
    }

    func testOfflineSubmitKeepsTheResumedChallenge() async {
        leavePendingChallenge()
        pendingFlow.submitResults = [.failure(StackError.Network(message: "offline"))]
        let sut = makeSUT()

        await sut.updateCode("123456")

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertNotNil(sut.uiState.errorMessage)
        XCTAssertTrue(autoReauth.discarded.isEmpty)
        XCTAssertEqual(signInsMade, 0)
    }

    func testRateLimitedOrUnavailableSubmitKeepsTheResumedChallenge() async {
        for status in [UInt16(429), 500, 502, 503] {
            leavePendingChallenge()
            pendingFlow.submitResults = [.failure(StackError.Http(status: status, message: "HTTP \(status)"))]
            signInsMade = 0
            let sut = makeSUT()

            await sut.updateCode("123456")

            XCTAssertEqual(sut.uiState.step, .code, "\(status)")
            XCTAssertTrue(sut.uiState.usesSavedPassword, "\(status)")
            XCTAssertNotNil(sut.uiState.errorMessage, "\(status)")
            XCTAssertTrue(autoReauth.discarded.isEmpty, "\(status): not a stale challenge")
            XCTAssertEqual(signInsMade, 0, "\(status)")
            XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
        }
    }

    func testUseDifferentPasswordDropsTheChallenge() {
        leavePendingChallenge()
        let sut = makeSUT()

        sut.useDifferentPassword()

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertFalse(sut.uiState.usesSavedPassword)
        XCTAssertEqual(autoReauth.discarded, [appleId])
    }

    func testTextMessageFallbackWorksOnTheResumedChallenge() async {
        leavePendingChallenge()
        pendingFlow.smsResults = [.success(needsCode)]
        let sut = makeSUT()

        await sut.requestSms(phoneId: AppleTrustedPhone.fixture.id)

        XCTAssertEqual(pendingFlow.requestedSmsPhoneIds, [AppleTrustedPhone.fixture.id])
        XCTAssertEqual(sut.uiState.codeMethod, .phone(phoneId: AppleTrustedPhone.fixture.id))
    }
}
