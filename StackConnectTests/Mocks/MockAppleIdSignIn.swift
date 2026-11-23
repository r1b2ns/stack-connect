import Foundation
import StackCoreRust
@testable import StackConnect

/// Scripted `AppleIdSignInProtocol`: the core's Apple ID sign-in without
/// Apple. Each call returns (or throws) the next scripted result and records
/// what it received. Never stores the password beyond the `starts` record the
/// tests assert on.
final class MockAppleIdSignIn: AppleIdSignInProtocol, @unchecked Sendable {

    struct Start: Equatable {
        let email: String
        let password: String
    }

    private let lock = NSLock()

    var startResults: [Result<AppleSignInStep, Error>] = []
    var submitResults: [Result<AppleSignInStep, Error>] = []
    var smsResults: [Result<AppleSignInStep, Error>] = []
    var finishResult: Result<Data, Error> = .success(Data("session-blob".utf8))

    private(set) var starts: [Start] = []
    private(set) var submittedCodes: [(code: String, method: AppleCodeMethod)] = []
    private(set) var requestedSmsPhoneIds: [UInt64] = []
    private(set) var finishCount = 0

    func start(email: String, password: String) async throws -> AppleSignInStep {
        try lock.withLock {
            starts.append(Start(email: email, password: password))
            return try Self.next(&startResults)
        }
    }

    func requestSms(phoneId: UInt64) async throws -> AppleSignInStep {
        try lock.withLock {
            requestedSmsPhoneIds.append(phoneId)
            return try Self.next(&smsResults)
        }
    }

    func submitCode(code: String, method: AppleCodeMethod) async throws -> AppleSignInStep {
        try lock.withLock {
            submittedCodes.append((code, method))
            return try Self.next(&submitResults)
        }
    }

    func teams() async -> [AppleTeam] { [] }

    func finish() async throws -> Data {
        try lock.withLock {
            finishCount += 1
            return try finishResult.get()
        }
    }

    private static func next(_ results: inout [Result<AppleSignInStep, Error>]) throws -> AppleSignInStep {
        guard !results.isEmpty else { throw StackError.Auth(message: "unscripted call") }
        return try results.removeFirst().get()
    }
}

/// In-memory `AppleSessionStatusTracking`.
final class MockAppleSessionStatus: AppleSessionStatusTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var expired = Set<String>()
    private(set) var markedExpired: [String] = []
    private(set) var markedValid: [String] = []

    func isExpired(appleId: String) -> Bool { lock.withLock { expired.contains(appleId) } }

    func expiredAppleIds() -> Set<String> { lock.withLock { expired } }

    func markExpired(appleId: String) {
        lock.withLock {
            expired.insert(appleId)
            markedExpired.append(appleId)
        }
    }

    func markValid(appleId: String) {
        lock.withLock {
            expired.remove(appleId)
            markedValid.append(appleId)
        }
    }
}

/// `AppleSessionRoleResolving` answering a fixed role per team.
final class MockAppleSessionRoleResolver: AppleSessionRoleResolving, @unchecked Sendable {
    var roles: [UInt64: AccountRole] = [:]
    private(set) var asked: [(appleId: String, teamId: UInt64)] = []

    func role(of appleId: String, in team: AppleWebSessionReference) async -> AccountRole {
        asked.append((appleId, team.teamId))
        return roles[team.teamId] ?? .unspecified
    }
}

extension AppleTeam {
    static func fixture(_ id: UInt64, _ name: String) -> AppleTeam {
        AppleTeam(providerId: id, name: name, publicProviderId: nil, contentTypes: ["SOFTWARE"])
    }
}

extension AppleTrustedPhone {
    static let fixture = AppleTrustedPhone(id: 7, maskedNumber: "+49 •••• •••••85", mode: "sms")
}
