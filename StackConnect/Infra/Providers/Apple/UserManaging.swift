import Foundation
import StackProtocols

/// Testable seam over the user-management calls the `UserDetail` module needs.
///
/// `AppleAccountConnection` already implements every one of these methods against
/// the Rust core; this protocol lets `UserDetailViewModel` depend on an
/// abstraction (Dependency Inversion) so tests can inject a mock instead of
/// hitting the network or the keychain. It mirrors the `SubmissionsServicing`
/// seam next to it.
///
/// The methods are declared as plain `async throws` (not `@MainActor`): the
/// concrete `AppleAccountConnection` is a `Sendable`, actor-agnostic type whose
/// methods are `nonisolated`. `@MainActor` ViewModels can still `await` them —
/// the call simply suspends off the main actor.
protocol UserManaging {
    /// Updates an active team member's roles + access flags. `roles` are raw ASC
    /// strings (primary role + additional resources). Not valid for pending invites.
    func updateUser(
        id: String,
        roles: [String],
        allAppsVisible: Bool,
        provisioningAllowed: Bool
    ) async throws

    /// Returns the IDs of the apps the user is scoped to (empty when none).
    func fetchUserVisibleApps(id: String) async throws -> [String]

    /// Full-replace of the user's visible-apps set (empty array clears scoping).
    func updateUserVisibleApps(id: String, appIds: [String]) async throws

    /// Removes an active member or cancels a pending invitation.
    func deleteUser(id: String, isPending: Bool) async throws

    /// Source of apps for the visible-apps picker.
    func fetchApps() async throws -> [StackProtocols.AppInfo]
}

// MARK: - Conformance

/// `AppleAccountConnection` already exposes matching method signatures, so the
/// conformance is purely declarative — no new code, just the protocol adoption.
extension AppleAccountConnection: UserManaging {}
