import Foundation

struct UserModel: Codable, Identifiable, Hashable {
    let id: String
    var firstName: String?
    var lastName: String?
    var email: String?
    var roles: [String]
    var allAppsVisible: Bool
    var provisioningAllowed: Bool
    var isPending: Bool
    var expirationDate: Date?

    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return parts.isEmpty ? (email ?? "–") : parts
    }

    var primaryRoleDisplayName: String {
        guard let first = roles.first else { return "–" }
        return Self.formatRole(first)
    }

    var rolesDisplayName: String {
        roles.map { Self.formatRole($0) }.joined(separator: ", ")
    }

    static func formatRole(_ role: String) -> String {
        switch role {
        case "ADMIN":                           return String(localized: "Admin")
        case "FINANCE":                         return String(localized: "Finance")
        case "ACCOUNT_HOLDER":                  return String(localized: "Account Holder")
        case "SALES":                           return String(localized: "Sales")
        case "MARKETING":                       return String(localized: "Marketing")
        case "APP_MANAGER":                     return String(localized: "App Manager")
        case "DEVELOPER":                       return String(localized: "Developer")
        case "ACCESS_TO_REPORTS":               return String(localized: "Access to Reports")
        case "CUSTOMER_SUPPORT":                return String(localized: "Customer Support")
        case "READ_ONLY":                       return String(localized: "Read Only")
        case "CREATE_APPS":                     return String(localized: "Create Apps")
        case "CLOUD_MANAGED_DEVELOPER_ID":      return String(localized: "Cloud Managed Developer ID")
        case "CLOUD_MANAGED_APP_DISTRIBUTION":  return String(localized: "Cloud Managed App Distribution")
        case "GENERATE_INDIVIDUAL_KEYS":        return String(localized: "Generate Individual Keys")
        default:
            return role.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
