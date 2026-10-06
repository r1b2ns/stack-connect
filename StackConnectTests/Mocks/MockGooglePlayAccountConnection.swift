import Foundation
import StackProtocols
@testable import StackConnect

/// In-memory `GooglePlayAccountConnecting`. Each call runs its handler, so a test
/// can return canned apps, throw, or inspect the caller while it is suspended
/// mid-call (e.g. to assert the cached list is already on screen). Calls are
/// counted; `credentials` records what the factory was given.
final class MockGooglePlayAccountConnection: GooglePlayAccountConnecting, @unchecked Sendable {

    /// What `validateCredentials()` does. Defaults to success.
    var validateHandler: @Sendable () async throws -> Void = {}

    /// What `fetchApps()` does. Defaults to an empty list.
    var fetchAppsHandler: @Sendable () async throws -> [StackProtocols.AppInfo] = { [] }

    private let lock = NSLock()
    private var _validateCallCount = 0
    private var _fetchAppsCallCount = 0
    private var _credentials: [GooglePlayCredentials] = []

    var validateCallCount: Int { lock.withLock { _validateCallCount } }
    var fetchAppsCallCount: Int { lock.withLock { _fetchAppsCallCount } }
    var credentials: [GooglePlayCredentials] { lock.withLock { _credentials } }

    /// Factory closure for the ViewModels' `connectionFactory` parameters: records
    /// the credentials and hands back this mock.
    func factory(_ credentials: GooglePlayCredentials) -> any GooglePlayAccountConnecting {
        lock.withLock { _credentials.append(credentials) }
        return self
    }

    func validateCredentials() async throws {
        lock.withLock { _validateCallCount += 1 }
        try await validateHandler()
    }

    func fetchApps() async throws -> [StackProtocols.AppInfo] {
        lock.withLock { _fetchAppsCallCount += 1 }
        return try await fetchAppsHandler()
    }
}

/// In-memory `GooglePlayAppAccessChecking` for the manual "add app" flow.
final class MockGooglePlayAppAccessChecker: GooglePlayAppAccessChecking, @unchecked Sendable {

    /// Error `verifyAccess(packageName:)` throws; `nil` means access is granted.
    var error: Error?

    private let lock = NSLock()
    private var _checkedPackageNames: [String] = []

    var checkedPackageNames: [String] { lock.withLock { _checkedPackageNames } }

    func verifyAccess(packageName: String) async throws {
        lock.withLock { _checkedPackageNames.append(packageName) }
        if let error { throw error }
    }
}
