import Foundation

struct CertificateModel: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let name: String
    let certificateType: String
    let platform: String?
    let serialNumber: String?
    let expirationDate: Date?
    let isActivated: Bool

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var typeDisplayName: String {
        switch certificateType {
        case "IOS_DEVELOPMENT":            return String(localized: "iOS Development")
        case "IOS_DISTRIBUTION":           return String(localized: "iOS Distribution")
        case "MAC_APP_DEVELOPMENT":        return String(localized: "Mac Development")
        case "MAC_APP_DISTRIBUTION":       return String(localized: "Mac Distribution")
        case "MAC_INSTALLER_DISTRIBUTION": return String(localized: "Mac Installer Distribution")
        case "DEVELOPMENT":                return String(localized: "Development")
        case "DISTRIBUTION":               return String(localized: "Distribution")
        case "DEVELOPER_ID_APPLICATION",
             "DEVELOPER_ID_APPLICATION_G2": return String(localized: "Developer ID Application")
        case "DEVELOPER_ID_KEXT",
             "DEVELOPER_ID_KEXT_G2":       return String(localized: "Developer ID Kext")
        case "PASS_TYPE_ID",
             "PASS_TYPE_ID_WITH_NFC":      return String(localized: "Pass Type ID")
        case "APPLE_PAY",
             "APPLE_PAY_MERCHANT_IDENTITY",
             "APPLE_PAY_PSP_IDENTITY",
             "APPLE_PAY_RSA":              return String(localized: "Apple Pay")
        case "IDENTITY_ACCESS":            return String(localized: "Identity Access")
        default:                           return certificateType
        }
    }
}
