import Combine
import Foundation
@testable import StackConnect

/// `AccountStatusProviding` answering fixed statuses, with a hand-driven
/// `changes` signal.
@MainActor
final class MockAccountStatusProvider: AccountStatusProviding {

    /// Statuses keyed by account id.
    var statusesById: [String: AccountStatus] = [:]
    private(set) var statusRequests: [String] = []

    private let subject = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    func sendChange() { subject.send(()) }

    func statuses(for accounts: [AccountModel]) -> [String: AccountStatus] {
        statusesById.filter { id, _ in accounts.contains { $0.id == id } }
    }

    func status(forAccountId accountId: String) async -> AccountStatus? {
        statusRequests.append(accountId)
        return statusesById[accountId]
    }
}

extension AccountStatus {
    /// Test shorthand; traps on an empty list (never used that way).
    static func of(_ issues: AccountStatusIssue...) -> AccountStatus {
        guard let status = AccountStatus(issues: issues) else { preconditionFailure("no issues") }
        return status
    }
}
