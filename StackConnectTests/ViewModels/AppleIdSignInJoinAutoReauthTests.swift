import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// Signing in again while the automatic sign-in runs for the same Apple ID:
/// the screen waits for it (no second sign-in, no second code) and applies
/// its outcome, and it keeps a new automatic attempt away while it runs.
@MainActor
final class AppleIdSignInJoinAutoReauthTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var status: MockAppleSessionStatus!
    private var autoReauth: MockAppleSessionAutoReauthenticator!
    /// The automatic attempt's core sign-in (Apple sent its code).
    private var pendingFlow: MockAppleIdSignIn!
    /// What `makeSignIn` builds for a sign-in of the screen's own.
    private var freshFlow: MockAppleIdSignIn!
    private var signInsMade = 0
    private var gate: AsyncGate!

    private let appleId = "dev@example.com"
    private var passwordKey: String { "applePassword.\(appleId)" }

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        status = MockAppleSessionStatus()
        autoReauth = MockAppleSessionAutoReauthenticator()
        pendingFlow = MockAppleIdSignIn()
        pendingFlow.finishResult = .success(Data("new-session".utf8))
        freshFlow = MockAppleIdSignIn()
        freshFlow.finishResult = .success(Data("own-session".utf8))
        signInsMade = 0
        gate = AsyncGate()
        keychain.set("saved", forKey: passwordKey)
        status.markExpired(appleId: appleId)
    }

    override func tearDown() async throws {
        await gate.open()
        storage = nil
        keychain = nil
        analytics = nil
        status = nil
        autoReauth = nil
        pendingFlow = nil
        freshFlow = nil
        gate = nil
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

    /// An automatic attempt in flight that ends with `outcome` once the gate
    /// opens, after `effect` (what the real attempt leaves behind).
    private func runAutomaticAttempt(_ outcome: AppleSessionAutoReauthOutcome, effect: @escaping @MainActor () -> Void = {}) {
        let gate = gate!
        autoReauth.inFlight[appleId] = Task { @MainActor in
            await gate.wait()
            effect()
            return outcome
        }
    }

    /// Opens the screen (its `.task`) while the attempt runs, checks the
    /// waiting state, then lets the attempt end.
    private func openWhileTheAttemptRuns(_ sut: AppleIdSignInViewModel, file: StaticString = #filePath, line: UInt = #line) async {
        let screen = Task { await sut.signInWithSavedPasswordIfAvailable() }
        await gate.waitForArrivals(1)
        await waitUntil { sut.uiState.isWorking }
        XCTAssertTrue(sut.uiState.isWorking, "shown working while it waits", file: file, line: line)
        XCTAssertEqual(sut.uiState.notice, String(localized: "Reconnecting Apple ID \(appleId)…"), file: file, line: line)
        XCTAssertTrue(sut.uiState.usesSavedPassword, "never the password field", file: file, line: line)
        await gate.open()
        await screen.value
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private var needsCode: AppleSignInStep {
        .needsCode(methods: [.trustedDevice], phones: [.fixture], codeLength: 6, delivery: .trustedDevices)
    }

    // MARK: - Outcomes

    func testDoneFinishesWithoutASecondSignIn() async {
        runAutomaticAttempt(.done) { [unowned self] in self.status.markValid(appleId: self.appleId) }
        let sut = makeSUT()

        await openWhileTheAttemptRuns(sut)

        XCTAssertEqual(sut.uiState.step, .finished, "finished like a successful sign-in")
        XCTAssertEqual(signInsMade, 0, "no second sign-in")
        XCTAssertTrue(freshFlow.starts.isEmpty)
        XCTAssertEqual(autoReauth.joined, [appleId])
        XCTAssertFalse(sut.uiState.isWorking)
        XCTAssertNil(sut.uiState.notice)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
    }

    func testNeedsCodeResumesThePendingChallengeWithoutANewCode() async {
        runAutomaticAttempt(.needsCode) { [unowned self] in
            self.autoReauth.challenges[self.appleId] = .fixture(appleId: self.appleId, flow: self.pendingFlow)
        }
        pendingFlow.submitResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()

        await openWhileTheAttemptRuns(sut)

        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertTrue(sut.uiState.usesSavedPassword, "the password isn't asked")
        XCTAssertEqual(signInsMade, 0, "no new sign-in, so no new code")

        await sut.updateCode("123456")

        XCTAssertEqual(pendingFlow.submittedCodes.map(\.code), ["123456"], "the automatic attempt's code is used")
        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertEqual(signInsMade, 0)
    }

    func testFailedShowsTheErrorAndKeepsTheSavedPasswordInUse() async {
        autoReauth.failures[appleId] = StackError.Http(status: 503, message: "Apple's sign-in service is unavailable (HTTP 503); try again later")
        runAutomaticAttempt(.failed)
        freshFlow.startResults = [.success(needsCode)]
        let sut = makeSUT()

        await openWhileTheAttemptRuns(sut)

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "Apple's sign-in service isn't responding. Try again later."))
        XCTAssertTrue(sut.uiState.usesSavedPassword, "never back to the password field")
        XCTAssertTrue(sut.uiState.canSignIn)
        XCTAssertEqual(signInsMade, 0, "no new attempt right away")
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")

        // A tap retries with the saved password, once nothing runs any more.
        await sut.signIn()

        XCTAssertEqual(freshFlow.starts, [.init(email: appleId, password: "saved")])
        XCTAssertEqual(sut.uiState.step, .code)
    }

    func testFailedWithoutAnErrorShowsTheGenericMessage() async {
        runAutomaticAttempt(.failed)
        let sut = makeSUT()

        await openWhileTheAttemptRuns(sut)

        XCTAssertEqual(sut.uiState.errorMessage, String(localized: "Apple didn't complete the sign-in."))
        XCTAssertTrue(sut.uiState.usesSavedPassword)
        XCTAssertEqual(signInsMade, 0)
    }

    func testInvalidCredentialsAsksForThePassword() async {
        runAutomaticAttempt(.invalidCredentials) { [unowned self] in
            self.keychain.removeObject(forKey: self.passwordKey)
        }
        let sut = makeSUT()

        await openWhileTheAttemptRuns(sut)

        XCTAssertEqual(sut.uiState.step, .credentials)
        XCTAssertFalse(sut.uiState.usesSavedPassword, "the password field is back")
        XCTAssertNil(sut.uiState.errorMessage)
        XCTAssertEqual(sut.uiState.notice, String(localized: "The saved password didn't work. It may have changed: enter your current Apple ID password."))
        XCTAssertEqual(signInsMade, 0)
        XCTAssertNil(keychain.string(forKey: passwordKey))
    }

    func testATapWhileTheAttemptRunsJoinsItToo() async {
        runAutomaticAttempt(.done)
        let sut = makeSUT()
        sut.emailDidChange()
        XCTAssertTrue(sut.uiState.usesSavedPassword)

        let tap = Task { await sut.signIn() }
        await gate.waitForArrivals(1)
        await gate.open()
        await tap.value

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertEqual(signInsMade, 0)
    }

    func testClosingWhileWaitingAppliesNothing() async {
        runAutomaticAttempt(.done)
        let sut = makeSUT()

        let screen = Task { await sut.signInWithSavedPasswordIfAvailable() }
        await gate.waitForArrivals(1)
        sut.discard()
        await gate.open()
        await screen.value

        XCTAssertNotEqual(sut.uiState.step, .finished)
        XCTAssertEqual(signInsMade, 0)
        XCTAssertTrue(autoReauth.manualSignIns.isEmpty)
    }

    func testWithoutAnAttemptInFlightTheSavedPasswordSignsIn() async {
        freshFlow.startResults = [.success(needsCode)]
        let sut = makeSUT()

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertTrue(autoReauth.joined.isEmpty)
        XCTAssertEqual(freshFlow.starts, [.init(email: appleId, password: "saved")])
    }

    // MARK: - Keeping the automatic sign-in away

    func testAManualSignInHoldsTheMarkUntilItEnds() async {
        freshFlow.startResults = [.success(needsCode)]
        freshFlow.submitResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()

        await sut.signInWithSavedPasswordIfAvailable()
        XCTAssertEqual(autoReauth.manualSignIns[appleId], 1, "held at the code step: no automatic attempt (and code) meanwhile")

        await sut.updateCode("123456")

        XCTAssertEqual(sut.uiState.step, .finished)
        XCTAssertTrue(autoReauth.manualSignIns.isEmpty, "released once finished")
    }

    func testAFailedManualSignInReleasesTheMark() async {
        freshFlow.startResults = [.failure(StackError.Network(message: "offline"))]
        let sut = makeSUT()

        await sut.signInWithSavedPasswordIfAvailable()

        XCTAssertTrue(autoReauth.manualSignIns.isEmpty)
        XCTAssertEqual(autoReauth.manualSignInLog, ["begin:\(appleId)", "end:\(appleId)"])
    }

    func testDiscardReleasesTheMark() async {
        freshFlow.startResults = [.success(needsCode)]
        let sut = makeSUT()
        await sut.signInWithSavedPasswordIfAvailable()
        XCTAssertEqual(autoReauth.manualSignIns[appleId], 1)

        sut.discard()

        XCTAssertTrue(autoReauth.manualSignIns.isEmpty, "a closed screen no longer keeps the automatic sign-in away")
    }

    func testAResumedChallengeHoldsTheMarkAndDiscardReleasesIt() {
        autoReauth.challenges[appleId] = .fixture(appleId: appleId, flow: pendingFlow)
        let sut = makeSUT()
        XCTAssertEqual(sut.uiState.step, .code)
        XCTAssertEqual(autoReauth.manualSignIns[appleId], 1)

        sut.discard()

        XCTAssertTrue(autoReauth.manualSignIns.isEmpty)
    }

    func testAddAccountNeverHoldsTheMark() async {
        freshFlow.startResults = [.success(needsCode)]
        let sut = makeSUT(.addAccounts)
        sut.uiState.email = appleId
        sut.uiState.password = "typed"

        await sut.signIn()

        XCTAssertTrue(autoReauth.manualSignInLog.isEmpty)
    }
}
