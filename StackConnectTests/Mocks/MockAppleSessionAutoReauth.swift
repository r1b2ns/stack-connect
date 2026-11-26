import Combine
import Foundation
import StackCoreRust
@testable import StackConnect

/// A core sign-in whose `start` waits on `gate` before answering like
/// `inner`, so a test can hold an automatic sign-in mid-flight.
final class GatedAppleIdSignIn: AppleIdSignInProtocol, @unchecked Sendable {

    let inner: MockAppleIdSignIn
    let gate = AsyncGate()

    init(inner: MockAppleIdSignIn) {
        self.inner = inner
    }

    func start(email: String, password: String) async throws -> AppleSignInStep {
        await gate.wait()
        return try await inner.start(email: email, password: password)
    }

    func requestSms(phoneId: UInt64) async throws -> AppleSignInStep {
        try await inner.requestSms(phoneId: phoneId)
    }

    func submitCode(code: String, method: AppleCodeMethod) async throws -> AppleSignInStep {
        try await inner.submitCode(code: code, method: method)
    }

    func teams() async -> [AppleTeam] { await inner.teams() }

    func finish() async throws -> Data { try await inner.finish() }
}

/// Scripted `AppleSessionAutoReauthenticating` for the screens that read the
/// automatic sign-in (Home, the app-wide prompt, the sign-in itself).
@MainActor
final class MockAppleSessionAutoReauthenticator: AppleSessionAutoReauthenticating {

    var states: [String: AppleSessionAutoReauthState] = [:]
    var challenges: [String: AppleSessionPendingChallenge] = [:]
    /// Apple IDs whose expiry `handlesExpiry(of:)` claims.
    var handledAppleIds = Set<String>()
    private(set) var discarded: [String] = []
    private(set) var expired: [String] = []

    private let subject = PassthroughSubject<AppleSessionAutoReauthEvent, Never>()
    var events: AnyPublisher<AppleSessionAutoReauthEvent, Never> { subject.eraseToAnyPublisher() }

    func send(_ event: AppleSessionAutoReauthEvent) {
        subject.send(event)
    }

    func state(for appleId: String) -> AppleSessionAutoReauthState? { states[appleId] }

    func pendingChallenge(for appleId: String) -> AppleSessionPendingChallenge? { challenges[appleId] }

    func discardPendingChallenge(for appleId: String) {
        discarded.append(appleId)
        challenges[appleId] = nil
        states[appleId] = nil
    }

    func handlesExpiry(of appleId: String) -> Bool { handledAppleIds.contains(appleId) }

    func sessionDidExpire(appleId: String) async -> AppleSessionAutoReauthOutcome? {
        expired.append(appleId)
        return nil
    }

    func appDidBecomeActive() async {}

    // MARK: Manual sign-in

    /// The attempt "in flight" per Apple ID: `inFlightOutcome` waits for it.
    var inFlight: [String: Task<AppleSessionAutoReauthOutcome, Never>] = [:]
    var failures: [String: Error] = [:]
    private(set) var manualSignIns: [String: Int] = [:]
    private(set) var manualSignInLog: [String] = []
    private(set) var joined: [String] = []

    func isAttemptInFlight(for appleId: String) -> Bool { inFlight[appleId] != nil }

    func inFlightOutcome(for appleId: String) async -> AppleSessionAutoReauthOutcome? {
        guard let task = inFlight[appleId] else { return nil }
        joined.append(appleId)
        let outcome = await task.value
        inFlight[appleId] = nil
        return outcome
    }

    func lastFailure(for appleId: String) -> Error? { failures[appleId] }

    func beginManualSignIn(for appleId: String) {
        manualSignIns[appleId, default: 0] += 1
        manualSignInLog.append("begin:\(appleId)")
    }

    func endManualSignIn(for appleId: String) {
        let count = manualSignIns[appleId] ?? 0
        manualSignIns[appleId] = count > 1 ? count - 1 : nil
        manualSignInLog.append("end:\(appleId)")
    }
}

extension AppleSessionPendingChallenge {
    static func fixture(
        appleId: String,
        flow: any AppleIdSignInProtocol,
        delivery: AppleCodeDelivery = .trustedDevices,
        codeLength: UInt8 = 6,
        createdAt: Date = Date()
    ) -> AppleSessionPendingChallenge {
        AppleSessionPendingChallenge(
            appleId: appleId,
            flow: flow,
            methods: [.trustedDevice, .phone(phoneId: AppleTrustedPhone.fixture.id)],
            phones: [.fixture],
            codeLength: codeLength,
            delivery: delivery,
            createdAt: createdAt
        )
    }
}
