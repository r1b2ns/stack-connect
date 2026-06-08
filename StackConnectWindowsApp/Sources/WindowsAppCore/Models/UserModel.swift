import Foundation

/// Foundation-pure user model for the Windows GUI.
///
/// Mirrors the shape of the iOS `UserModel` but avoids `String(localized:)`
/// (Apple-only) and computed display helpers that reference localized catalogs.
/// Format helpers live as plain methods here; the Views layer can localize them
/// at the presentation boundary.
public struct UserModel: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var roles: [String]
    public var allAppsVisible: Bool
    public var provisioningAllowed: Bool
    public var isPending: Bool

    public init(
        id: String,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        roles: [String] = [],
        allAppsVisible: Bool = false,
        provisioningAllowed: Bool = false,
        isPending: Bool = false
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.roles = roles
        self.allAppsVisible = allAppsVisible
        self.provisioningAllowed = provisioningAllowed
        self.isPending = isPending
    }

    /// Formatted display name: "First Last", or the email, or a dash.
    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return parts.isEmpty ? (email ?? "–") : parts
    }

    /// The first role, formatted for display.
    public var primaryRoleDisplayName: String {
        guard let first = roles.first else { return "–" }
        return Self.formatRole(first)
    }

    /// All roles joined by commas.
    public var rolesDisplayName: String {
        roles.map { Self.formatRole($0) }.joined(separator: ", ")
    }

    /// Formats a raw API role string into a human-readable label.
    public static func formatRole(_ role: String) -> String {
        role.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
