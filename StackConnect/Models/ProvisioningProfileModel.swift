import Foundation

struct ProvisioningProfileModel: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let profileType: String
    let profileState: String
    let platform: String?
    let uuid: String?
    let bundleId: String?
    let createdDate: Date?
    let expirationDate: Date?

    var isActive: Bool {
        profileState == "ACTIVE"
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var typeDisplayName: String {
        switch profileType {
        case "IOS_APP_DEVELOPMENT":         return String(localized: "iOS Development")
        case "IOS_APP_STORE":               return String(localized: "iOS App Store")
        case "IOS_APP_ADHOC":               return String(localized: "iOS Ad Hoc")
        case "IOS_APP_INHOUSE":             return String(localized: "iOS In-House")
        case "MAC_APP_DEVELOPMENT":         return String(localized: "Mac Development")
        case "MAC_APP_STORE":               return String(localized: "Mac App Store")
        case "MAC_APP_DIRECT":              return String(localized: "Mac Direct")
        case "TVOS_APP_DEVELOPMENT":        return String(localized: "tvOS Development")
        case "TVOS_APP_STORE":              return String(localized: "tvOS App Store")
        case "TVOS_APP_ADHOC":              return String(localized: "tvOS Ad Hoc")
        case "TVOS_APP_INHOUSE":            return String(localized: "tvOS In-House")
        case "MAC_CATALYST_APP_DEVELOPMENT": return String(localized: "Mac Catalyst Development")
        case "MAC_CATALYST_APP_STORE":      return String(localized: "Mac Catalyst App Store")
        case "MAC_CATALYST_APP_DIRECT":     return String(localized: "Mac Catalyst Direct")
        default:                            return profileType
        }
    }
}
