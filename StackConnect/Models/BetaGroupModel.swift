import Foundation

struct BetaGroupModel: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var isInternalGroup: Bool
    var createdDate: Date?
    var hasAccessToAllBuilds: Bool
    var isPublicLinkEnabled: Bool
    var publicLink: String?
    var publicLinkId: String?
    var publicLinkLimit: Int?
    var isPublicLinkLimitEnabled: Bool
    var isFeedbackEnabled: Bool
    var testerCount: Int?
    var buildCount: Int?
}

struct TeamMemberModel: Codable, Identifiable, Hashable {
    let id: String
    var firstName: String?
    var lastName: String?
    var username: String?
    var roles: [String]

    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return parts.isEmpty ? (username ?? "–") : parts
    }

    var rolesDisplayName: String {
        roles.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: ", ")
    }
}

struct BetaTesterModel: Codable, Identifiable, Hashable {
    let id: String
    var firstName: String?
    var lastName: String?
    var email: String?
    var inviteType: String?
    var state: String?

    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return parts.isEmpty ? (email ?? "–") : parts
    }

    var stateDisplayName: String {
        switch state {
        case "NOT_INVITED":  return String(localized: "Not Invited")
        case "INVITED":      return String(localized: "Invited")
        case "ACCEPTED":     return String(localized: "Accepted")
        case "INSTALLED":    return String(localized: "Installed")
        case "REVOKED":      return String(localized: "Revoked")
        default:             return state ?? "–"
        }
    }

    var stateColor: AppStoreStateColor {
        switch state {
        case "INSTALLED":   return .green
        case "ACCEPTED":    return .blue
        case "INVITED":     return .yellow
        case "NOT_INVITED": return .gray
        case "REVOKED":     return .red
        default:            return .gray
        }
    }

    var stateIcon: String {
        switch state {
        case "INSTALLED":   return "checkmark.circle.fill"
        case "ACCEPTED":    return "person.crop.circle.badge.checkmark"
        case "INVITED":     return "envelope.fill"
        case "NOT_INVITED": return "person.crop.circle.badge.minus"
        case "REVOKED":     return "xmark.circle.fill"
        default:            return "person.crop.circle"
        }
    }
}
