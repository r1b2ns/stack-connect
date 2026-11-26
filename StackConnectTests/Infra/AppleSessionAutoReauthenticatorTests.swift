import Combine
import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// The automatic sign-in of an expired Apple ID session with the saved
/// password: every outcome, the retry rule (no code spam), coalescing, and
/// foreground only.
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

    func testPendingChallengeExpiresAfterItsLifetimeAndANewAttemptIsDue() async {
        expireWithSavedPassword()
        flow.startResults = [.success(needsCode), .success(needsCode)]
        let sut = makeSUT()
        await sut.sessionDidExpire(appleId: appleId)

        now = now.addingTimeInterval(AppleSessionAutoReauthenticator.challengeLifetime + 1)

        XCTAssertNil(sut.pendingChallenge(for: appleId))
        XCTAssertNil(sut.state(for: appleId))
        XCTAssertTrue(sut.handlesExpiry(of: appleId), "a new attempt is due: no prompt asking for the password")
        await sut.appDidBecomeActive()
        XCTAssertEqual(flow.starts.count, 2, "a new code once the old one expired")
        XCTAssertNotNil(sut.pendingChallenge(for: appleId))
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

    // MARK: - Transient failures (429, 5xx, network): kept and retried

    private var transientFailures: [(String, Error)] {
        [
            ("429", StackError.Http(status: 429, message: "Too Many Requests")),
            ("500", StackError.Http(status: 500, message: "Internal Server Error")),
            ("502", StackError.Http(status: 502, message: "Bad Gateway")),
            ("503", StackError.Http(status: 503, message: "Apple's sign-in service is unavailable (HTTP 503); try again later")),
            ("network", StackError.Network(message: "offline")),
            ("offline", OfflineError.noConnection),
            ("timeout", URLError(.timedOut))
        ]
    }

    func testTransientFailuresKeepThePasswordAndRetryOnTheNextForeground() async {
        for (name, error) in transientFailures {
            setUpFreshAttempt()
            flow.startResults = [.failure(error), .success(.done(teams: []))]
            let sut = makeSUT()

            let outcome = await sut.sessionDidExpire(appleId: appleId)

            XCTAssertEqual(outcome, .failed, name)
            XCTAssertEqual(keychain.string(forKey: passwordKey), "saved", "\(name): never treated as a wrong password")
            XCTAssertTrue(outcome?.fallsBackToManualSignIn == true, name)

            await sut.appDidBecomeActive()

            XCTAssertEqual(flow.starts.count, 2, "\(name): the next foreground retries")
            XCTAssertEqual(status.markedValid, [appleId], name)
        }
    }

    func testTransientFailuresAreClassifiedAsTransientNotWrongPassword() {
        for (name, error) in transientFailures {
            XCTAssertEqual(AppleSessionRenewal.failureKind(of: error), .transient, name)
            XCTAssertFalse(AppleSessionRenewal.isWrongPassword(error), name)
        }
        XCTAssertEqual(AppleSessionRenewal.failureKind(of: StackError.InvalidCredentials(message: "wrong")), .wrongPassword)
        XCTAssertEqual(AppleSessionRenewal.failureKind(of: StackError.Http(status: 401, message: "Unauthorized")), .other,
                       "a raw HTTP 401 is not the core's wrong password")
        XCTAssertEqual(AppleSessionRenewal.failureKind(of: StackError.Http(status: 404, message: "Not Found")), .other)
        XCTAssertEqual(AppleSessionRenewal.failureKind(of: StackError.Auth(message: "locked")), .other)
        XCTAssertEqual(AppleSessionRenewal.failureKind(of: StackError.Http(status: 600, message: "?")), .other)
    }

    func testAFailedAttemptIsRetriedOnAnExpiryOnlyAfterTheInterval() async {
        expireWithSavedPassword()
        flow.startResults = [.failure(StackError.Http(status: 503, message: "unavailable")), .success(.done(teams: []))]
        let sut = makeSUT()
        await sut.sessionDidExpire(appleId: appleId)

        let tooSoon = await sut.sessionDidExpire(appleId: appleId)
        XCTAssertNil(tooSoon, "an expiry is posted for every refused call: no retry on each one")
        XCTAssertFalse(sut.handlesExpiry(of: appleId), "the prompt (which uses the saved password) shows meanwhile")

        now = now.addingTimeInterval(AppleSessionAutoReauthenticator.failureRetryInterval)
        XCTAssertTrue(sut.handlesExpiry(of: appleId))
        let retried = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(retried, .done)
        XCTAssertEqual(flow.starts.count, 2)
        XCTAssertEqual(flow.starts.map(\.password), ["saved", "saved"])
    }

    func testAFailedAttemptIsRetriedAfterARelaunch() async {
        expireWithSavedPassword()
        flow.startResults = [.failure(StackError.Network(message: "offline")), .success(.done(teams: []))]
        await makeSUT().sessionDidExpire(appleId: appleId)

        let relaunched = makeSUT()
        await relaunched.appDidBecomeActive()

        XCTAssertEqual(flow.starts.count, 2, "a blip at launch never blocks the next launch")
        XCTAssertEqual(status.markedValid, [appleId])
    }

    func testNoRetryAfterTheSavedPasswordWasRefused() async {
        expireWithSavedPassword()
        flow.startResults = [.failure(StackError.InvalidCredentials(message: "the Apple ID or password is incorrect"))]
        let sut = makeSUT()
        await sut.sessionDidExpire(appleId: appleId)

        now = now.addingTimeInterval(AppleSessionAutoReauthenticator.challengeLifetime + 1)
        await sut.appDidBecomeActive()
        let again = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertNil(again)
        XCTAssertEqual(flow.starts.count, 1, "no password left to try")
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

    func testNoNewCodeWhileTheChallengeIsAlive() async {
        expireWithSavedPassword()
        flow.startResults = [.success(needsCode), .success(needsCode)]
        let sut = makeSUT()
        await sut.sessionDidExpire(appleId: appleId)

        now = now.addingTimeInterval(AppleSessionAutoReauthenticator.challengeLifetime - 1)
        let second = await sut.sessionDidExpire(appleId: appleId)
        await sut.appDidBecomeActive()

        XCTAssertNil(second, "no second code while the first one works")
        XCTAssertEqual(flow.starts.count, 1)
        XCTAssertTrue(sut.handlesExpiry(of: appleId))
    }

    func testARelaunchThatLostTheChallengeSignsInAgain() async {
        expireWithSavedPassword()
        flow.startResults = [.success(needsCode), .success(needsCode)]
        await makeSUT().sessionDidExpire(appleId: appleId)

        let relaunched = makeSUT()
        XCTAssertNil(relaunched.pendingChallenge(for: appleId), "the challenge lived in memory only")
        XCTAssertTrue(relaunched.handlesExpiry(of: appleId), "no prompt asking for the password")
        await relaunched.appDidBecomeActive()

        XCTAssertEqual(flow.starts.count, 2, "the lost challenge's code can't be used: a new attempt")
        XCTAssertNotNil(relaunched.pendingChallenge(for: appleId))
    }

    func testALeftChallengeIsNotReplacedBeforeItsLifetime() async {
        expireWithSavedPassword()
        flow.startResults = [.success(needsCode), .success(needsCode)]
        let sut = makeSUT()
        await sut.sessionDidExpire(appleId: appleId)

        // The user went back from the code screen.
        sut.discardPendingChallenge(for: appleId)
        let tooSoon = await sut.sessionDidExpire(appleId: appleId)
        XCTAssertNil(tooSoon, "no new code right after the user left one")
        XCTAssertFalse(sut.handlesExpiry(of: appleId), "the manual sign-in (saved password) takes over")

        now = now.addingTimeInterval(AppleSessionAutoReauthenticator.challengeLifetime)
        let later = await sut.sessionDidExpire(appleId: appleId)
        XCTAssertEqual(later, .needsCode)
        XCTAssertEqual(flow.starts.count, 2)
    }

    func testTheLegacyAttemptMarksAreDroppedSoAStuckAppleIdIsAttempted() async {
        defaults.set([appleId], forKey: AppleSessionAutoReauthenticator.legacyAttemptedDefaultsKey)
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: []))]
        let sut = makeSUT()

        XCTAssertNil(defaults.object(forKey: AppleSessionAutoReauthenticator.legacyAttemptedDefaultsKey))
        XCTAssertTrue(sut.handlesExpiry(of: appleId))
        let outcome = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(outcome, .done)
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
            self.defaults.data(forKey: AppleSessionAutoReauthenticator.attemptsDefaultsKey) == nil
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

    // MARK: - Next to a manual sign-in

    func testNoAutomaticAttemptWhileAManualSignInIsOpen() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: []))]
        let sut = makeSUT()
        sut.beginManualSignIn(for: "  DEV@example.com ")

        let outcome = await sut.sessionDidExpire(appleId: appleId)
        await sut.appDidBecomeActive()

        XCTAssertNil(outcome)
        XCTAssertTrue(flow.starts.isEmpty, "never a second sign-in (and code) next to the manual one")
        XCTAssertTrue(sut.handlesExpiry(of: appleId), "no prompt over the open sign-in")

        sut.endManualSignIn(for: appleId)
        let later = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertEqual(later, .done, "due again once the manual sign-in ended")
        XCTAssertEqual(flow.starts.count, 1)
    }

    func testManualSignInsAreCounted() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: []))]
        let sut = makeSUT()
        sut.beginManualSignIn(for: appleId)
        sut.beginManualSignIn(for: appleId)

        sut.endManualSignIn(for: appleId)
        let stillOpen = await sut.sessionDidExpire(appleId: appleId)
        sut.endManualSignIn(for: appleId)
        sut.endManualSignIn(for: appleId)
        let closed = await sut.sessionDidExpire(appleId: appleId)

        XCTAssertNil(stillOpen, "one screen is still open")
        XCTAssertEqual(closed, .done, "an extra end never goes negative")
    }

    func testInFlightOutcomeJoinsTheRunningAttempt() async {
        expireWithSavedPassword()
        flow.startResults = [.success(.done(teams: []))]
        let gated = GatedAppleIdSignIn(inner: flow)
        signIn = gated
        let sut = makeSUT()
        let none = await sut.inFlightOutcome(for: appleId)
        XCTAssertNil(none, "nil right away when nothing runs")
        XCTAssertFalse(sut.isAttemptInFlight(for: appleId))

        let attempt = Task { await sut.sessionDidExpire(appleId: appleId) }
        await gated.gate.waitForArrivals(1)
        XCTAssertTrue(sut.isAttemptInFlight(for: "Dev@Example.com"))
        let joined = Task { await sut.inFlightOutcome(for: appleId) }
        await gated.gate.open()

        let joinedOutcome = await joined.value
        let attemptOutcome = await attempt.value
        XCTAssertEqual(joinedOutcome, .done)
        XCTAssertEqual(attemptOutcome, .done)
        XCTAssertEqual(flow.starts.count, 1)
        XCTAssertFalse(sut.isAttemptInFlight(for: appleId))
    }

    func testLastFailureKeepsTheErrorOfTheFailedAttempt() async {
        expireWithSavedPassword()
        flow.startResults = [.failure(StackError.Http(status: 503, message: "unavailable")), .success(.done(teams: []))]
        let sut = makeSUT()

        await sut.sessionDidExpire(appleId: appleId)

        guard case StackError.Http(let status, _)? = sut.lastFailure(for: appleId) as? StackError else {
            return XCTFail("the 503 is kept for the manual screen")
        }
        XCTAssertEqual(status, 503)

        await sut.appDidBecomeActive()
        XCTAssertNil(sut.lastFailure(for: appleId), "cleared by the next attempt")
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
