import Foundation

/// Testable seam over listing an App Store Connect team's members (`GET /v1/users`).
///
/// `AppleAccountConnection` already implements `fetchUsers()` against the Rust
/// core; this one-method protocol lets callers that only need the member list
/// (e.g. Home's "ask the Account Holder" share action) depend on an abstraction,
/// so tests can inject a stub instead of hitting the network or the keychain. It
/// is kept separate from `UserManaging` on purpose (Interface Segregation): those
/// callers never edit users.
///
/// `Sendable` because the call suspends off the caller's actor: the concrete
/// `AppleAccountConnection` is an actor-agnostic `@unchecked Sendable` type whose
/// methods are `nonisolated`, and `@MainActor` ViewModels simply `await` it.
protocol TeamUsersFetching: Sendable {
    /// Returns every member of the team, including pending invitations.
    func fetchUsers() async throws -> [UserModel]
}

// MARK: - Conformance

/// `AppleAccountConnection` already exposes a matching method, so the conformance
/// is purely declarative.
extension AppleAccountConnection: TeamUsersFetching {}
