import Combine
import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// The automatic sign-in of an expired Apple ID session with the saved
/// password: every outcome, once per expiry, coalescing, and foreground only.
@MainActor
final class AppleSessionAutoReauthenticatorTests: XCTestCase {

    private var keychain: MockKeyStorable!
    private var status: MockAppleSessionStatus!
    private var analytics: MockAnalyticsTracker!
    private var center: NotificationCenter!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var flow: MockAppleIdSignIn!
    private var signIn: (any AppleIdSignInProtocol)!
    private var savedSessionsPassed: [Data?] = []
    private var isActive = true
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var events: [AppleSessionAutoReauthEvent] = []
    private var cancellables = Set<AnyCancellable>()
    private var sync: MockSyncFollowUp!

    private let appleId = "dev@example.com"
    private let oldBlob = Data("old-session".utf8)
    private let newBlob = Data("new-session".utf8)

    private var passwordKey: String { "applePassword.\(appleId)" }
    private var sessionKey: String { "appleSession.\(appleId)" }

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeyStorable()
        status = MockAppleSessionStatus()
        analytics = MockAnalyticsTracker()
        center = NotificationCenter()
        suiteName = "AppleSessionAutoReauthenticatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        flow = MockAppleIdSignIn()
        flow.finishResult = .success(newBlob)
        signIn = flow
        savedSessionsPassed = []
        isActive = true
        events = []
        cancellables = []
        sync = MockSyncFollowUp()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        keychain = nil
        status = nil
        analytics = nil
        center = nil
        defaults = nil
        flow = nil
        signIn = nil
        cancellables = []
        try await super.tearDown()
    }

    private func makeSUT() -> AppleSessionAutoReauthenticator {
        let sut = AppleSessionAutoReauthenticator(
            keychain: keychain,
            sessionStatus: status,
            defaults: defaults,
            analytics: analytics,
            center: center,
            isAppActive: { [unowned self] in self.isActive },
            now: { [unowned self] in self.now },
            makeSignIn: { [unowned self] saved in
                self.savedSessionsPassed.append(saved)
                return self.signIn
            },
            sync: sync
        )
        sut.events.sink { [unowned self] in self.events.append($0) }.store(in: &cancellables)
        return sut
    }

    /// An expired session with a saved password: the attempt is due.
    private func expireWithSavedPassword() {
        keychain.set(oldBlob, forKey: sessionKey)
        keychain.set("saved", forKey: passwordKey)
        status.markExpired(appleId: appleId)
    }

    private var needsCode: AppleSignInStep {
        .needsCode(methods: [.trustedDevice], phones: [.fixture], codeLength: 6, delivery: .trustedDevices)
    }

    private var autoReauthEvents: [AnalyticsEvent] { analytics.actions(of: .appleSessionAutoReauth) }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
    }

    // MARK: - Outcomes

    func testDoneRenewsTheSessionAndKeepsThePassword() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(flow.starts, [.init(email: appleId, password: "saved")])
        XCTAssertEqual(savedSessionsPassed, [oldBlob], "signs in over the saved session (trusted-device cookies)")
        XCTAssertEqual(keychain.data(forKey: sessionKey), newBlob, "saved like the manual sign-in again")
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
        XCTAssertEqual(status.markedValid, [appleId])
        XCTAssertNil(sut.state(for: appleId))
        XCTAssertNil(sut.pendingChallenge(for: appleId))
        XCTAssertEqual(events, [.started(appleId: appleId), .finished(appleId: appleId, outcome: .done)])
        XCTAssertEqual(autoReauthEvents.count, 1)
        XCTAssertEqual(autoReauthEvents.first?.parameters[AnalyticsParameterKey.result], .string(AnalyticsResult.success.rawValue))
        XCTAssertEqual(autoReauthEvents.first?.parameters[AnalyticsParameterKey.outcome], .string("done"))
    }

    func testNeedsCodeKeepsThePendingChallenge() async throws {
        expireWithSavedPassword()
        flow.startResults = [.success(needsCode)]
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(outcome, .needsCode)
        let challenge = try XCTUnwrap(sut.pendingChallenge(for: appleId))
        XCTAssertTrue(challenge.flow === flow, "the same core sign-in, so the code Apple sent still works")
        XCTAssertEqual(challenge.codeLength, 6)
        XCTAssertEqual(challenge.delivery, .trustedDevices)
        XCTAssertEqual(sut.state(for: appleId), .awaitingCode(.trustedDevices))
        XCTAssertTrue(sut.handlesExpiry(of: appleId), "the prompt stays away: the Home banner asks for the code")
        XCTAssertTrue(status.markedValid.isEmpty)
        XCTAssertEqual(flow.finishCount, 0)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
        XCTAssertEqual(autoReauthEvents.first?.parameters[AnalyticsParameterKey.result], .string(AnalyticsResult.pending.rawValue))
        XCTAssertEqual(autoReauthEvents.first?.parameters[AnalyticsParameterKey.outcome], .string("needs_code"))
    }

    func testPendingChallengeExpiresAfterItsLifetime() async {
        expireWithSavedPassword()
        flow.startResults = [.success(needsCode)]
        let sut = makeSUT()
        await sut.sessionDidExpire(appleId: appleId)

        now = now.addingTimeInterval(AppleSessionAutoReauthenticator.challengeLifetime + 1)

        XCTAssertNil(sut.pendingChallenge(for: appleId))
        XCTAssertNil(sut.state(for: appleId))
        XCTAssertFalse(sut.handlesExpiry(of: appleId), "the manual sign-in takes over")
    }

    func testDiscardingThePendingChallengeForgetsIt() async {
        expireWithSavedPassword()
        flow.startResults = [.success(needsCode)]
        let sut = makeSUT()
        await sut.sessionDidExpire(appleId: appleId)

        sut.discardPendingChallenge(for: appleId)

        XCTAssertNil(sut.pendingChallenge(for: appleId))
    }

    func testInvalidCredentialsDeletesTheSavedPassword() async {
        expireWithSavedPassword()
        flow.startResults = [.failure(StackError.InvalidCredentials(message: "the Apple ID or password is incorrect"))]
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(outcome, .invalidCredentials)
        XCTAssertNil(keychain.string(forKey: passwordKey))
        XCTAssertEqual(keychain.data(forKey: sessionKey), oldBlob, "the session is untouched")
        XCTAssertTrue(status.markedValid.isEmpty)
        XCTAssertNil(sut.state(for: appleId))
        XCTAssertFalse(sut.handlesExpiry(of: appleId))
        XCTAssertEqual(events.last, .finished(appleId: appleId, outcome: .invalidCredentials))
        XCTAssertEqual(autoReauthEvents.first?.parameters[AnalyticsParameterKey.errorCategory], .string("invalid_credentials"))
    }

    func testRateLimitKeepsTheSavedPassword() async {
        expireWithSavedPassword()
        flow.startResults = [.failure(StackError.Http(status: 429, message: "Too Many Requests"))]
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
        XCTAssertNil(sut.state(for: appleId))
        XCTAssertFalse(sut.handlesExpiry(of: appleId), "the manual sign-in takes over")
        XCTAssertEqual(autoReauthEvents.first?.parameters[AnalyticsParameterKey.result], .string(AnalyticsResult.failure.rawValue))
        XCTAssertEqual(autoReauthEvents.first?.parameters[AnalyticsParameterKey.outcome], .string("failed"))
    }

    func testAcknowledgementFailsAndKeepsThePassword() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.needsAcknowledgement)]
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
        XCTAssertNil(sut.pendingChallenge(for: appleId))
        XCTAssertEqual(autoReauthEvents.first?.parameters[AnalyticsParameterKey.errorCategory], .string("forbidden"))
    }

    func testFinishFailureFailsAndKeepsThePassword() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: []))]
        flow.finishResult = .failure(StackError.Auth(message: "not signed in"))
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(keychain.data(forKey: sessionKey), oldBlob)
        XCTAssertEqual(keychain.string(forKey: passwordKey), "saved")
        XCTAssertTrue(status.markedValid.isEmpty)
    }

    // MARK: - Sync after a success

    func testDoneSyncsTheAccountsAfterTheRunInFlight() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: [.fixture(1, "Alpha")]))]
        let sut = makeSUT()

        await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(sync.requests, [.init(mode: .full, trigger: .foreground, screen: nil)])
    }

    func testOtherOutcomesDontSync() async {
        let failures: [Result<AppleSignInStep, Error>] = [
            .success(needsCode),
            .failure(StackError.InvalidCredentials(message: "the Apple ID or password is incorrect")),
            .failure(StackError.Http(status: 429, message: "Too Many Requests")),
            .success(.needsAcknowledgement)
        ]
        for result in failures {
            setUpFreshAttempt()
            flow.startResults = [result]
            let sut = makeSUT()

            let outcome = await sut.sessionDidExpire(appleId: appleId)

            XCTAssertNotEqual(outcome, .done)
            XCTAssertTrue(sync.requests.isEmpty, "\(String(describing: outcome))")
        }
    }

    /// A new expiry with fresh stores, for several attempts in one test.
    private func setUpFreshAttempt() {
        defaults.removePersistentDomain(forName: suiteName)
        keychain = MockKeyStorable()
        status = MockAppleSessionStatus()
        flow = MockAppleIdSignIn()
        flow.finishResult = .success(newBlob)
        signIn = flow
        sync = MockSyncFollowUp()
        expireWithSavedPassword()
    }

    // MARK: - When it runs

    func testNoSavedPasswordMeansNoAttempt() async {
        keychain.set(oldBlob, forKey: sessionKey)
        status.markExpired(appleId: appleId)
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertNil(outcome)
        XCTAssertTrue(flow.starts.isEmpty)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(autoReauthEvents.isEmpty)
        XCTAssertFalse(sut.handlesExpiry(of: appleId), "the prompt shows as before")
    }

    func testAWorkingSessionIsNotAttempted() async {
        keychain.set("saved", forKey: passwordKey)
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertNil(outcome)
        XCTAssertTrue(flow.starts.isEmpty)
    }

    func testOneAttemptPerExpiry() async {
        expireWithSavedPassword()
        flow.startResults = [.failure(StackError.Network(message: "offline")), .success(.done(teams: []))]
        let sut = makeSUT()

        await sut.sessionDidExpire(appleId: appleId)
        let second = await sut.sessionDidExpire(appleId: appleId)
        await sut.appDidBecomeActive()

        XCTAssertNil(second, "no retry loop")
        XCTAssertEqual(flow.starts.count, 1)
    }

    func testTheAttemptMarkSurvivesARelaunch() async {
        expireWithSavedPassword()
        flow.startResults = [.success(needsCode), .success(needsCode)]
        await makeSUT().sessionDidExpire(appleId: appleId)

        let relaunched = makeSUT()
        let outcome = await relaunched.sessionDidExpire(appleId: appleId)

        XCTAssertNil(outcome, "no second code after a relaunch")
        XCTAssertEqual(flow.starts.count, 1)
        XCTAssertNil(relaunched.pendingChallenge(for: appleId), "the challenge lived in memory only")
    }

    func testANewExpiryAfterTheSessionWorkedAgainIsAttempted() async {
        expireWithSavedPassword()
        flow.startResults = [.failure(StackError.Network(message: "offline")), .success(.done(teams: []))]
        let sut = makeSUT()
        sut.start()
        await sut.sessionDidExpire(appleId: appleId)

        // Signed in by hand, then expired again later.
        status.markValid(appleId: appleId)
        center.post(name: .signInStatusDidChange, object: nil)
        await waitUntil {
            (self.defaults.stringArray(forKey: AppleSessionAutoReauthenticator.attemptedDefaultsKey) ?? []).isEmpty
        }
        status.markExpired(appleId: appleId)
        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(flow.starts.count, 2)
    }

    func testConcurrentTriggersShareOneAttempt() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: []))]
        let gated = GatedAppleIdSignIn(inner: flow)
        signIn = gated
        let sut = makeSUT()

        let first = Task { await sut.sessionDidExpire(appleId: appleId) }
        await gated.gate.waitForArrivals(1)
        XCTAssertEqual(sut.state(for: appleId), .reconnecting)
        XCTAssertTrue(sut.handlesExpiry(of: appleId))
        let second = Task { await sut.sessionDidExpire(appleId: "  DEV@example.com ") }
        let third = Task { await sut.appDidBecomeActive() }
        await gated.gate.settle(yields: 100, sleep: .milliseconds(20))
        await gated.gate.open()

        let outcomes = [await first.value, await second.value]
        await third.value
        XCTAssertEqual(outcomes, [.done, .done], "the second trigger joins the running attempt")
        XCTAssertEqual(flow.starts.count, 1)
        let arrivals = await gated.gate.arrivals
        XCTAssertEqual(arrivals, 1)
        XCTAssertEqual(events.filter { if case .started = $0 { return true } else { return false } }.count, 1)
    }

    func testNotTriggeredInTheBackground() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: []))]
        isActive = false
        let sut = makeSUT()

        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertNil(outcome)
        XCTAssertTrue(flow.starts.isEmpty, "never from the background refresh")
        XCTAssertTrue(sut.handlesExpiry(of: appleId), "still due once the app is active")

        isActive = true
        await sut.appDidBecomeActive()

        XCTAssertEqual(flow.starts.count, 1)
        XCTAssertEqual(status.markedValid, [appleId])
    }

    func testTheExpiryNotificationStartsTheAttempt() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: []))]
        let sut = makeSUT()
        sut.start()

        center.post(name: .appleSessionDidExpire, object: appleId, userInfo: [AppleSessionStatusStore.isNewKey: true])

        await waitUntil { self.status.markedValid == [self.appleId] }
        XCTAssertEqual(flow.starts.count, 1)
    }

    func testTheSessionStatusStoreListsExpiredAppleIds() {
        let suite = "AppleSessionAutoReauthenticatorTests.store.\(UUID().uuidString)"
        let storeDefaults = UserDefaults(suiteName: suite)!
        defer { storeDefaults.removePersistentDomain(forName: suite) }
        let store = AppleSessionStatusStore(defaults: storeDefaults, center: NotificationCenter())

        store.markExpired(appleId: "A@example.com")
        store.markExpired(appleId: "b@example.com")
        store.markValid(appleId: "b@example.com")

        XCTAssertEqual(store.expiredAppleIds(), ["a@example.com"])
    }
}

/// Records the follow-up syncs the reauthenticator asks for.
@MainActor
private final class MockSyncFollowUp: SyncFollowUpRequesting {

    struct Request: Equatable {
        let mode: SyncMode
        let trigger: SyncTrigger
        let screen: AnalyticsScreen?
    }

    private(set) var requests: [Request] = []

    func requestFollowUpSync(mode: SyncMode, trigger: SyncTrigger, screen: AnalyticsScreen?) -> Task<Void, Never> {
        requests.append(Request(mode: mode, trigger: trigger, screen: screen))
        return Task {}
    }
}
