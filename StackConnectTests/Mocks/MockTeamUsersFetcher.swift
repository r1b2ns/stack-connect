import Foundation
@testable import StackConnect

/// In-memory `TeamUsersFetching` stub. Each call runs `handler`, so a test can
/// return a fixed member list, throw, or run code while the caller is suspended
/// mid-fetch (e.g. to observe a loading flag). Calls are counted.
final class MockTeamUsersFetcher: TeamUsersFetching, @unchecked Sendable {

    struct StubError: Error {}

    /// What `fetchUsers()` does. Set it before the call under test.
    var handler: @Sendable () async throws -> [UserModel]

    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.withLock { _callCount }
    }

    init(users: [UserModel] = []) {
        handler = { users }
    }

    init(error: Error) {
        handler = { throw error }
    }

    func fetchUsers() async throws -> [UserModel] {
        lock.withLock { _callCount += 1 }
        return try await handler()
    }
}
