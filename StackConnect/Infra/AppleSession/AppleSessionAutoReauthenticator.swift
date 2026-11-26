import Combine
import Foundation
import StackCoreRust
import StackProtocols
import UIKit

// MARK: - Model

/// Where Apple sent the code of an automatic sign-in that stopped at the
/// two-factor step.
enum AppleSessionCodeDestination: Equatable, Sendable {
    /// Shown on the trusted Apple devices.
    case trustedDevices
    /// Texted to a trusted phone number.
    case phone
    /// Not sent yet: the user picks a phone number on the code screen.
    case notSent

    init(_ delivery: AppleCodeDelivery) {
        switch delivery {
        case .trustedDevices: self = .trustedDevices
        case .phone: self = .phone
        case .notSent: self = .notSent
        }
    }
}

/// What the automatic sign-in is doing for an Apple ID.
enum AppleSessionAutoReauthState: Equatable, Sendable {
    /// Signing in with the saved password, in the background.
    case reconnecting
    /// Apple asked for a two-factor code: the sign-in waits for the user
    /// (`AppleSessionPendingChallenge`).
    case awaitingCode(AppleSessionCodeDestination)
}

/// How an automatic sign-in ended.
enum AppleSessionAutoReauthOutcome: String, Equatable, Sendable {
    /// Apple accepted the saved session and password: the session is renewed.
    case done = "done"
    /// Apple sent a code: kept as a pending challenge for the user to finish.
    case needsCode = "needs_code"
    /// Apple refused the saved password: it was removed.
    case invalidCredentials = "invalid_credentials"
    /// Anything else (network, rate limit, HTTP 5xx, acknowledgement,
    /// storage): the saved password is kept, the manual sign-in takes over
    /// (it uses the saved password too) and the next trigger retries.
    case failed = "failed"

    /// The manual "sign in again" (prompt, banner) takes over.
    var fallsBackToManualSignIn: Bool {
        self == .invalidCredentials || self == .failed
    }
}

enum AppleSessionAutoReauthEvent: Equatable, Sendable {
    case started(appleId: String)
    case finished(appleId: String, outcome: AppleSessionAutoReauthOutcome)
}

/// A core sign-in that Apple left at the two-factor step: the code was sent,
/// so the user only has to type it (the password is not asked again). In
/// memory only: gone with the app.
struct AppleSessionPendingChallenge {
    let appleId: String
    let flow: any AppleIdSignInProtocol
    let methods: [AppleCodeMethod]
    let phones: [AppleTrustedPhone]
    let codeLength: UInt8
    let delivery: AppleCodeDelivery
    let createdAt: Date
}

// MARK: - Protocols

/// What the automatic sign-in is doing, for the chips and the banner.
@MainActor
protocol AppleSessionAutoReauthStateProviding: AnyObject {
    /// `nil` when no automatic sign-in runs or waits for `appleId`.
    func state(for appleId: String) -> AppleSessionAutoReauthState?
}

/// The pending two-factor challenge an automatic sign-in left, for the
/// sign-in screen to resume.
@MainActor
protocol AppleSessionPendingChallengeProviding: AnyObject {
    /// The challenge still waiting for `appleId`'s code, `nil` when there is
    /// none or it is too old.
    func pendingChallenge(for appleId: String) -> AppleSessionPendingChallenge?
    /// Forgets `appleId`'s challenge (finished, abandoned or stale).
    func discardPendingChallenge(for appleId: String)
}

/// The manual sign-in's side of the automatic one, so the two never run at
/// once for an Apple ID (each run can make Apple send a code): the manual
/// sign-in waits for an automatic attempt in flight instead of starting its
/// own, and no automatic attempt starts while a manual sign-in is open.
@MainActor
protocol AppleSessionManualSignInCoordinating: AppleSessionPendingChallengeProviding {
    /// An automatic attempt is running for `appleId`.
    func isAttemptInFlight(for appleId: String) -> Bool
    /// Waits for the automatic attempt running for `appleId`.
    /// - Returns: its outcome, or `nil` right away when none runs.
    func inFlightOutcome(for appleId: String) async -> AppleSessionAutoReauthOutcome?
    /// Why `appleId`'s last automatic attempt failed (in memory only), for
    /// the manual screen's message; `nil` when it didn't fail on an error.
    func lastFailure(for appleId: String) -> Error?
    /// A manual sign-in started for `appleId`: no automatic attempt starts
    /// for it until the matching `endManualSignIn(for:)`.
    func beginManualSignIn(for appleId: String)
    /// The manual sign-in of `appleId` ended (finished, failed or closed).
    func endManualSignIn(for appleId: String)
}

/// Signs in again with the saved password when an Apple ID session expires,
/// in the foreground only, without sending Apple codes in a loop.
@MainActor
protocol AppleSessionAutoReauthenticating: AppleSessionAutoReauthStateProviding, AppleSessionManualSignInCoordinating {
    /// Emits on the main actor when an attempt starts and ends.
    var events: AnyPublisher<AppleSessionAutoReauthEvent, Never> { get }
    /// Whether the automatic sign-in takes care of `appleId`'s expiry (it
    /// runs, waits for a code, or is due as soon as the app is active), so
    /// the manual prompt should not show for it.
    func handlesExpiry(of appleId: String) -> Bool
    /// `appleId`'s session expired: signs in with its saved password if it
    /// is due. A call while an attempt runs joins it.
    /// - Returns: the outcome, or `nil` when no attempt ran.
    @discardableResult
    func sessionDidExpire(appleId: String) async -> AppleSessionAutoReauthOutcome?
    /// The app is active (launch or back from the background): attempts
    /// every expired Apple ID that is due.
    func appDidBecomeActive() async
}

// MARK: - Implementation

/// Re-authenticates an expired Apple ID session on its own with the password
/// saved on the device (`ApplePasswordKeychainStore`).
///
/// Apple often accepts the saved session's trusted-device cookies with the
/// password and asks no code; when it does ask, the code is already sent, so
/// the challenge is kept for the user to finish from the Home banner.
///
/// Rules, per Apple ID (shared by all its team accounts), from the last
/// attempt's record (`AttemptRecord`, persisted with its time):
/// - Concurrent triggers **join** the running attempt.
/// - After `.failed` (network, 429, 5xx...): the next foreground retries;
///   another expiry retries once `failureRetryInterval` passed (an expiry
///   is posted for every refused call, so it can't retry on each one).
/// - After `.needsCode`: **no new attempt while its challenge is alive**
///   (no second code); a new one once the challenge is gone (a relaunch
///   lost it) or older than `challengeLifetime`. A challenge the user left
///   (back from the code screen) is not replaced before that lifetime: the
///   manual sign-in, which uses the saved password too, takes over.
/// - After `.invalidCredentials` the password is deleted: nothing retries.
/// - A session that works again forgets its record.
/// - **Never next to a manual sign-in** of the same Apple ID
///   (`AppleSessionManualSignInCoordinating`): the manual one joins a
///   running attempt, and no attempt starts while a manual one is open.
/// - **Foreground only**: an expiry seen by the background refresh waits for
///   the app to become active.
/// - Only with a saved password; without one nothing changes.
/// - **A success syncs the accounts** (`SyncFollowUpRequesting`): after
///   the run in flight, if any, which couldn't use the renewed session.
///
/// The password is read from the Keychain for the call only and never
/// logged; the challenge lives in memory only.
@MainActor
final class AppleSessionAutoReauthenticator: AppleSessionAutoReauthenticating {

    static let shared = AppleSessionAutoReauthenticator(sync: SyncService.shared)

    /// `UserDefaults` key of the last attempt of each expired Apple ID
    /// (`[normalized e-mail: AttemptRecord]` as JSON, no secret).
    static let attemptsDefaultsKey = "appleSession.autoReauthAttempts"
    /// The former "already attempted" marks (a string array), which stopped
    /// every retry after one attempt. Removed on launch.
    static let legacyAttemptedDefaultsKey = "appleSession.autoReauthAttemptedAppleIds"
    /// How long a pending challenge is offered (Apple's codes expire).
    static let challengeLifetime: TimeInterval = 10 * 60
    /// After a failed attempt, how long an expiry (not the foreground) waits
    /// before trying again.
    static let failureRetryInterval: TimeInterval = 60

    /// The last automatic attempt of an Apple ID whose session is still
    /// expired.
    struct AttemptRecord: Codable, Equatable {
        enum Outcome: String, Codable { case failed, needsCode }
        let outcome: Outcome
        let at: Date
    }

    /// What asks for an attempt.
    enum Trigger { case expiry, foreground }

    var events: AnyPublisher<AppleSessionAutoReauthEvent, Never> { subject.eraseToAnyPublisher() }

    private let renewal: AppleSessionRenewal
    private let sessionStatus: AppleSessionStatusTracking
    private let defaults: UserDefaults
    private let analytics: AnalyticsTracking
    private let center: NotificationCenter
    private let isAppActive: @MainActor () -> Bool
    private let now: () -> Date
    /// Syncs the accounts once a session is renewed (`nil`: no sync, as in
    /// unit tests that don't check it).
    private let sync: (any SyncFollowUpRequesting)?

    private let subject = PassthroughSubject<AppleSessionAutoReauthEvent, Never>()
    private var inFlight: [String: Task<AttemptResult, Never>] = [:]
    private var challenges: [String: AppleSessionPendingChallenge] = [:]
    /// Apple IDs whose challenge the user left this launch (not lost).
    private var discardedChallenges = Set<String>()
    /// Open manual sign-ins per Apple ID (`beginManualSignIn`).
    private var manualSignIns: [String: Int] = [:]
    /// The error of each Apple ID's last failed attempt, in memory only.
    private var lastErrors: [String: Error] = [:]
    private var observers: [NSObjectProtocol] = []

    init(
        keychain: KeyStorable = KeychainStorable.shared,
        sessionStatus: AppleSessionStatusTracking = AppleSessionStatusStore.shared,
        defaults: UserDefaults = .standard,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        center: NotificationCenter = .default,
        isAppActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
        now: @escaping () -> Date = Date.init,
        makeSignIn: AppleSessionRenewal.SignInFactory? = nil,
        sync: (any SyncFollowUpRequesting)? = nil
    ) {
        self.sync = sync
        self.renewal = AppleSessionRenewal(keychain: keychain, sessionStatus: sessionStatus, makeSignIn: makeSignIn)
        self.sessionStatus = sessionStatus
        self.defaults = defaults
        self.analytics = analytics
        self.center = center
        self.isAppActive = isAppActive
        self.now = now
        if defaults.object(forKey: Self.legacyAttemptedDefaultsKey) != nil {
            // The old marks blocked any retry: dropped, so a stuck Apple ID is
            // attempted again.
            defaults.removeObject(forKey: Self.legacyAttemptedDefaultsKey)
        }
    }

    /// Starts listening: an expiry (`.appleSessionDidExpire`), the app
    /// becoming active, and a session that works again (which clears its
    /// attempt record and challenge). Called once, by the app (never in a
    /// unit-test host).
    func start() {
        guard observers.isEmpty else { return }
        observers.append(center.addObserver(forName: .appleSessionDidExpire, object: nil, queue: .main) { [weak self] note in
            guard let appleId = note.object as? String else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.sessionDidExpire(appleId: appleId) }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.appDidBecomeActive() }
            }
        })
        observers.append(center.addObserver(forName: .signInStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.forgetRecoveredSessions() }
        })
    }

    // MARK: - State

    func state(for appleId: String) -> AppleSessionAutoReauthState? {
        let id = AppleSessionKeychainStore.normalized(appleId)
        if inFlight[id] != nil { return .reconnecting }
        if let challenge = pendingChallenge(for: id) {
            return .awaitingCode(AppleSessionCodeDestination(challenge.delivery))
        }
        return nil
    }

    func pendingChallenge(for appleId: String) -> AppleSessionPendingChallenge? {
        let id = AppleSessionKeychainStore.normalized(appleId)
        guard let challenge = challenges[id] else { return nil }
        guard now().timeIntervalSince(challenge.createdAt) < Self.challengeLifetime,
              sessionStatus.isExpired(appleId: id) else {
            challenges[id] = nil
            return nil
        }
        return challenge
    }

    func discardPendingChallenge(for appleId: String) {
        let id = AppleSessionKeychainStore.normalized(appleId)
        guard challenges.removeValue(forKey: id) != nil else { return }
        discardedChallenges.insert(id)
        center.postSignInStatusDidChange()
    }

    func handlesExpiry(of appleId: String) -> Bool {
        let id = AppleSessionKeychainStore.normalized(appleId)
        // An open manual sign-in handles it too: no prompt over it.
        if inFlight[id] != nil || pendingChallenge(for: id) != nil || isManualSignInOpen(id) { return true }
        return isDue(id, trigger: .expiry) && renewal.passwordStore.hasPassword(for: id)
    }

    /// Whether the record of `id` allows a new attempt on `trigger` (see
    /// the type's rules). The caller checked that nothing runs.
    private func isDue(_ id: String, trigger: Trigger) -> Bool {
        if pendingChallenge(for: id) != nil { return false }
        guard let record = records()[id] else { return true }
        let age = now().timeIntervalSince(record.at)
        switch record.outcome {
        case .failed:
            return trigger == .foreground || age >= Self.failureRetryInterval
        case .needsCode:
            return age >= Self.challengeLifetime || !discardedChallenges.contains(id)
        }
    }

    // MARK: - Triggers

    @discardableResult
    func sessionDidExpire(appleId: String) async -> AppleSessionAutoReauthOutcome? {
        await attemptIfDue(appleId: appleId, trigger: .expiry)
    }

    private func attemptIfDue(appleId: String, trigger: Trigger) async -> AppleSessionAutoReauthOutcome? {
        let id = AppleSessionKeychainStore.normalized(appleId)
        if let running = inFlight[id] {
            return await running.value.outcome
        }
        guard sessionStatus.isExpired(appleId: id), isDue(id, trigger: trigger) else { return nil }
        guard !isManualSignInOpen(id) else {
            Log.print.info("[AppleSessionAutoReauth] A manual sign-in is open for the Apple ID: no automatic sign-in")
            return nil
        }
        guard isAppActive() else {
            Log.print.info("[AppleSessionAutoReauth] The app isn't active: the automatic sign-in waits for the foreground")
            return nil
        }
        guard let password = renewal.passwordStore.password(for: id) else { return nil }

        Log.print.info("[AppleSessionAutoReauth] Signing in again with the saved password")
        let task = Task { await self.attempt(appleId: id, password: password) }
        inFlight[id] = task
        subject.send(.started(appleId: id))
        center.postSignInStatusDidChange()

        let result = await task.value
        let outcome = result.outcome
        inFlight[id] = nil
        record(outcome, for: id)
        track(result)
        subject.send(.finished(appleId: id, outcome: outcome))
        if outcome == .done {
            // The renewed Apple ID's accounts sync now, whatever screen is
            // open. A follow-up, not `syncAll`: the run started with the app
            // (at the same time as this attempt) can't use the new session.
            sync?.requestFollowUpSync(mode: .full, trigger: .foreground, screen: nil)
        }
        if outcome != .done {
            // `.done` already posted it (`markValid`).
            center.postSignInStatusDidChange()
        }
        return outcome
    }

    func appDidBecomeActive() async {
        forgetRecoveredSessions()
        let ids = sessionStatus.expiredAppleIds()
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { _ = await self.attemptIfDue(appleId: id, trigger: .foreground) }
            }
        }
    }

    // MARK: - Manual sign-in

    func isAttemptInFlight(for appleId: String) -> Bool {
        inFlight[AppleSessionKeychainStore.normalized(appleId)] != nil
    }

    func inFlightOutcome(for appleId: String) async -> AppleSessionAutoReauthOutcome? {
        guard let running = inFlight[AppleSessionKeychainStore.normalized(appleId)] else { return nil }
        return await running.value.outcome
    }

    func lastFailure(for appleId: String) -> Error? {
        lastErrors[AppleSessionKeychainStore.normalized(appleId)]
    }

    func beginManualSignIn(for appleId: String) {
        manualSignIns[AppleSessionKeychainStore.normalized(appleId), default: 0] += 1
    }

    func endManualSignIn(for appleId: String) {
        let id = AppleSessionKeychainStore.normalized(appleId)
        guard let count = manualSignIns[id] else { return }
        manualSignIns[id] = count > 1 ? count - 1 : nil
    }

    private func isManualSignInOpen(_ id: String) -> Bool {
        manualSignIns[id] != nil
    }

    // MARK: - Attempt

    /// An attempt's outcome, with why it failed (analytics only).
    private struct AttemptResult {
        let outcome: AppleSessionAutoReauthOutcome
        var failure: AnalyticsErrorCategory?
    }

    private func attempt(appleId: String, password: String) async -> AttemptResult {
        lastErrors[appleId] = nil
        do {
            let flow = try renewal.makeFlow(reusingSessionOf: appleId)
            let step = try await flow.start(email: appleId, password: password)
            switch step {
            case .done:
                try await renewal.storeSession(of: flow, appleId: appleId, password: password, savesPassword: true)
                Log.print.info("[AppleSessionAutoReauth] Signed in again without a code: the Apple ID session was replaced")
                return AttemptResult(outcome: .done)
            case let .needsCode(methods, phones, codeLength, delivery):
                challenges[appleId] = AppleSessionPendingChallenge(
                    appleId: appleId,
                    flow: flow,
                    methods: methods,
                    phones: phones,
                    codeLength: codeLength,
                    delivery: delivery,
                    createdAt: now()
                )
                Log.print.info("[AppleSessionAutoReauth] Apple asked for a code: kept the sign-in for the user to finish")
                return AttemptResult(outcome: .needsCode)
            case .needsAcknowledgement:
                Log.print.notice("[AppleSessionAutoReauth] The Apple ID needs action at appleid.apple.com: manual sign-in")
                return AttemptResult(outcome: .failed, failure: .forbidden)
            }
        } catch {
            lastErrors[appleId] = error
            switch AppleSessionRenewal.failureKind(of: error) {
            case .wrongPassword:
                // The only failure that removes the saved password.
                Log.print.notice("[AppleSessionAutoReauth] Apple refused the saved password: removed it from the Keychain")
                renewal.passwordStore.deletePassword(for: appleId)
                return AttemptResult(outcome: .invalidCredentials, failure: .invalidCredentials)
            case .transient:
                Log.print.notice("[AppleSessionAutoReauth] Apple or the network couldn't answer (\(error.localizedDescription, privacy: .public)): kept the saved password, retrying on the next trigger")
            case .other:
                Log.print.error("[AppleSessionAutoReauth] The automatic sign-in failed: \(error.localizedDescription, privacy: .public)")
            }
            return AttemptResult(outcome: .failed, failure: AnalyticsErrorCategory(connectionError: error))
        }
    }

    // MARK: - Attempt records

    /// The records, `[:]` when none or unreadable (then every Apple ID is due).
    private func records() -> [String: AttemptRecord] {
        guard let data = defaults.data(forKey: Self.attemptsDefaultsKey),
              let records = try? JSONDecoder().decode([String: AttemptRecord].self, from: data) else { return [:] }
        return records
    }

    private func saveRecords(_ records: [String: AttemptRecord]) {
        if records.isEmpty {
            defaults.removeObject(forKey: Self.attemptsDefaultsKey)
        } else if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.attemptsDefaultsKey)
        }
    }

    /// Keeps what the next trigger needs: `.failed` and `.needsCode` are
    /// recorded; a renewed session or a removed password needs nothing.
    private func record(_ outcome: AppleSessionAutoReauthOutcome, for id: String) {
        var all = records()
        switch outcome {
        case .failed:
            all[id] = AttemptRecord(outcome: .failed, at: now())
        case .needsCode:
            all[id] = AttemptRecord(outcome: .needsCode, at: now())
            discardedChallenges.remove(id)
        case .done, .invalidCredentials:
            all[id] = nil
        }
        saveRecords(all)
    }

    /// A session that works again (signed in by hand, a successful call, or
    /// its last account deleted) starts afresh on its next expiry, and its
    /// challenge is obsolete.
    private func forgetRecoveredSessions() {
        let expired = sessionStatus.expiredAppleIds()
        let all = records()
        let kept = all.filter { expired.contains($0.key) }
        if kept.count != all.count {
            saveRecords(kept)
        }
        for id in challenges.keys where !expired.contains(id) {
            challenges[id] = nil
        }
        discardedChallenges.formIntersection(expired)
    }

    // MARK: - Analytics

    /// `apple_session_auto_reauth`: `success` (done), `pending` (needs_code)
    /// or `failure` with `error_category`, and the `outcome` itself.
    private func track(_ attempt: AttemptResult) {
        let result: AnalyticsResult
        var parameters: [String: AnalyticsValue] = [AnalyticsParameterKey.outcome: .string(attempt.outcome.rawValue)]
        switch attempt.outcome {
        case .done:
            result = .success
        case .needsCode:
            result = .pending
        case .invalidCredentials, .failed:
            result = .failure
            parameters.merge((attempt.failure ?? .unknown).parameters) { _, new in new }
        }
        analytics.track(.action(.appleSessionAutoReauth, on: nil, result: result, parameters: parameters))
    }
}
