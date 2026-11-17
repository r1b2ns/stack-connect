import Foundation
@testable import StackConnect

/// In-memory `GooglePlayUsersConnecting`: an editable users list behind the
/// same calls the screens make. Every call is recorded; `failNext` makes the
/// next call of a kind throw.
final class MockGooglePlayUsersConnection: GooglePlayUsersConnecting, @unchecked Sendable {

    enum Call: Equatable {
        case fetch(developerId: String)
        case invite(email: String, accountPermissions: [String], grants: [GooglePlayGrantModel], expiration: Date?)
        case update(email: String, accountPermissions: [String], expiration: Date?)
        case delete(email: String)
        case setGrant(email: String, packageName: String, permissions: [String])
        case deleteGrant(email: String, packageName: String)
    }

    enum Kind: Hashable {
        case fetch, invite, update, delete, setGrant, deleteGrant
    }

    private let lock = NSLock()
    private var _users: [GooglePlayUserModel]
    private var _calls: [Call] = []
    private var _failures: [Kind: Error] = [:]

    init(users: [GooglePlayUserModel] = []) {
        _users = users
    }

    var users: [GooglePlayUserModel] { lock.withLock { _users } }
    var calls: [Call] { lock.withLock { _calls } }

    /// The next call of `kind` throws `error` (once).
    func failNext(_ kind: Kind, with error: Error) {
        lock.withLock { _failures[kind] = error }
    }

    func factory(_ credentials: GooglePlayCredentials) -> any GooglePlayUsersConnecting { self }

    private func record(_ call: Call, _ kind: Kind) throws {
        try lock.withLock {
            _calls.append(call)
            if let error = _failures.removeValue(forKey: kind) { throw error }
        }
    }

    func fetchUsers(developerId: String) async throws -> [GooglePlayUserModel] {
        try record(.fetch(developerId: developerId), .fetch)
        return users
    }

    func inviteUser(developerId: String, email: String, accountPermissions: [String], grants: [GooglePlayGrantModel], expiration: Date?) async throws -> GooglePlayUserModel {
        try record(.invite(email: email, accountPermissions: accountPermissions, grants: grants, expiration: expiration), .invite)
        let user = GooglePlayUserModel(email: email, accessState: .invited, expirationTime: expiration,
                                       developerAccountPermissions: accountPermissions, grants: grants)
        lock.withLock { _users.append(user) }
        return user
    }

    func updateUser(developerId: String, email: String, accountPermissions: [String], expiration: Date?) async throws -> GooglePlayUserModel {
        try record(.update(email: email, accountPermissions: accountPermissions, expiration: expiration), .update)
        return lock.withLock {
            guard let index = _users.firstIndex(where: { $0.matches(email: email) }) else {
                return GooglePlayUserModel(email: email)
            }
            _users[index].developerAccountPermissions = accountPermissions
            _users[index].expirationTime = expiration
            return _users[index]
        }
    }

    func deleteUser(developerId: String, email: String) async throws {
        try record(.delete(email: email), .delete)
        lock.withLock { _users.removeAll { $0.matches(email: email) } }
    }

    func setGrant(developerId: String, email: String, packageName: String, permissions: [String]) async throws -> GooglePlayGrantModel {
        try record(.setGrant(email: email, packageName: packageName, permissions: permissions), .setGrant)
        let grant = GooglePlayGrantModel(packageName: packageName, appLevelPermissions: permissions)
        lock.withLock {
            if let index = _users.firstIndex(where: { $0.matches(email: email) }) {
                _users[index].grants.removeAll { $0.packageName == packageName }
                _users[index].grants.append(grant)
            }
        }
        return grant
    }

    func deleteGrant(developerId: String, email: String, packageName: String) async throws {
        try record(.deleteGrant(email: email, packageName: packageName), .deleteGrant)
        lock.withLock {
            if let index = _users.firstIndex(where: { $0.matches(email: email) }) {
                _users[index].grants.removeAll { $0.packageName == packageName }
            }
        }
    }
}
