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
    /// Anything else (network, rate limit, acknowledgement, storage): the
    /// saved password is kept and the manual sign-in takes over.
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

/// Signs in again with the saved password when an Apple ID session expires,
/// once per expiry, in the foreground only.
@MainActor
protocol AppleSessionAutoReauthenticating: AppleSessionAutoReauthStateProviding, AppleSessionPendingChallengeProviding {
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
/// Rules:
/// - **Once per expiry and Apple ID**, shared by all its team accounts:
///   concurrent triggers join the running attempt, and an Apple ID already
///   attempted is not tried again until its session works again (the mark
///   is persisted, so a relaunch does not send another code).
/// - **Foreground only**: an expiry seen by the background refresh waits for
///   the app to become active.
/// - Only with a saved password; without one nothing changes.
///
/// The password is read from the Keychain for the call only and never
/// logged; the challenge lives in memory only.
@MainActor
final class AppleSessionAutoReauthenticator: AppleSessionAutoReauthenticating {

    static let shared = AppleSessionAutoReauthenticator()

    /// `UserDefaults` key of the Apple IDs already attempted for their
    /// current expiry (normalized e-mails, no secret).
    static let attemptedDefaultsKey = "appleSession.autoReauthAttemptedAppleIds"
    /// How long a pending challenge is offered (Apple's codes expire).
    static let challengeLifetime: TimeInterval = 10 * 60

    var events: AnyPublisher<AppleSessionAutoReauthEvent, Never> { subject.eraseToAnyPublisher() }

    private let renewal: AppleSessionRenewal
    private let sessionStatus: AppleSessionStatusTracking
    private let defaults: UserDefaults
    private let analytics: AnalyticsTracking
    private let center: NotificationCenter
    private let isAppActive: @MainActor () -> Bool
    private let now: () -> Date

    private let subject = PassthroughSubject<AppleSessionAutoReauthEvent, Never>()
    private var inFlight: [String: Task<AttemptResult, Never>] = [:]
    private var challenges: [String: AppleSessionPendingChallenge] = [:]
    private var observers: [NSObjectProtocol] = []

    init(
        keychain: KeyStorable = KeychainStorable.shared,
        sessionStatus: AppleSessionStatusTracking = AppleSessionStatusStore.shared,
        defaults: UserDefaults = .standard,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        center: NotificationCenter = .default,
        isAppActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
        now: @escaping () -> Date = Date.init,
        makeSignIn: AppleSessionRenewal.SignInFactory? = nil
    ) {
        self.renewal = AppleSessionRenewal(keychain: keychain, sessionStatus: sessionStatus, makeSignIn: makeSignIn)
        self.sessionStatus = sessionStatus
        self.defaults = defaults
        self.analytics = analytics
        self.center = center
        self.isAppActive = isAppActive
        self.now = now
    }

    /// Starts listening: an expiry (`.appleSessionDidExpire`), the app
    /// becoming active, and a session that works again (which clears its
    /// attempt mark and challenge). Called once, by the app (never in a
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
        center.postSignInStatusDidChange()
    }

    func handlesExpiry(of appleId: String) -> Bool {
        let id = AppleSessionKeychainStore.normalized(appleId)
        if inFlight[id] != nil || pendingChallenge(for: id) != nil { return true }
        return !attempted().contains(id) && renewal.passwordStore.hasPassword(for: id)
    }

    // MARK: - Triggers

    @discardableResult
    func sessionDidExpire(appleId: String) async -> AppleSessionAutoReauthOutcome? {
        let id = AppleSessionKeychainStore.normalized(appleId)
        if let running = inFlight[id] {
            return await running.value.outcome
        }
        guard sessionStatus.isExpired(appleId: id), !attempted().contains(id), challenges[id] == nil else { return nil }
        guard isAppActive() else {
            Log.print.info("[AppleSessionAutoReauth] The app isn't active: the automatic sign-in waits for the foreground")
            return nil
        }
        guard let password = renewal.passwordStore.password(for: id) else { return nil }

        markAttempted(id)
        Log.print.info("[AppleSessionAutoReauth] Signing in again with the saved password")
        let task = Task { await self.attempt(appleId: id, password: password) }
        inFlight[id] = task
        subject.send(.started(appleId: id))
        center.postSignInStatusDidChange()

        let result = await task.value
        let outcome = result.outcome
        inFlight[id] = nil
        track(result)
        subject.send(.finished(appleId: id, outcome: outcome))
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
                group.addTask { await self.sessionDidExpire(appleId: id) }
            }
        }
    }

    // MARK: - Attempt

    /// An attempt's outcome, with why it failed (analytics only).
    private struct AttemptResult {
        let outcome: AppleSessionAutoReauthOutcome
        var failure: AnalyticsErrorCategory?
    }

    private func attempt(appleId: String, password: String) async -> AttemptResult {
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
            if AppleSessionRenewal.isWrongPassword(error) {
                Log.print.notice("[AppleSessionAutoReauth] Apple refused the saved password: removed it from the Keychain")
                renewal.passwordStore.deletePassword(for: appleId)
                return AttemptResult(outcome: .invalidCredentials, failure: .invalidCredentials)
            }
            Log.print.error("[AppleSessionAutoReauth] The automatic sign-in failed: \(error.localizedDescription, privacy: .public)")
            return AttemptResult(outcome: .failed, failure: AnalyticsErrorCategory(connectionError: error))
        }
    }

    // MARK: - Attempt marks

    private func attempted() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.attemptedDefaultsKey) ?? [])
    }

    private func markAttempted(_ appleId: String) {
        var ids = attempted()
        ids.insert(appleId)
        defaults.set(ids.sorted(), forKey: Self.attemptedDefaultsKey)
    }

    /// A session that works again (signed in by hand, a successful call, or
    /// its last account deleted) can be attempted on its next expiry, and its
    /// challenge is obsolete.
    private func forgetRecoveredSessions() {
        let expired = sessionStatus.expiredAppleIds()
        let marks = attempted()
        let kept = marks.intersection(expired)
        if kept != marks {
            defaults.set(kept.sorted(), forKey: Self.attemptedDefaultsKey)
        }
        for id in challenges.keys where !expired.contains(id) {
            challenges[id] = nil
        }
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
