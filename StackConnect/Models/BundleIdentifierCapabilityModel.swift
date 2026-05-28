import Foundation

struct BundleIdentifierCapabilityModel: Identifiable, Hashable, Codable {
    let id: String
    let capabilityType: String

    var displayName: String {
        Self.displayName(for: capabilityType)
    }

    static func displayName(for capabilityType: String) -> String {
        switch capabilityType {
        case "ICLOUD":                          return "iCloud"
        case "IN_APP_PURCHASE":                 return "In-App Purchase"
        case "GAME_CENTER":                     return "Game Center"
        case "PUSH_NOTIFICATIONS":              return "Push Notifications"
        case "WALLET":                          return "Wallet"
        case "INTER_APP_AUDIO":                 return "Inter-App Audio"
        case "MAPS":                            return "Maps"
        case "ASSOCIATED_DOMAINS":              return "Associated Domains"
        case "PERSONAL_VPN":                    return "Personal VPN"
        case "APP_GROUPS":                      return "App Groups"
        case "HEALTHKIT":                       return "HealthKit"
        case "HOMEKIT":                         return "HomeKit"
        case "WIRELESS_ACCESSORY_CONFIGURATION":return "Wireless Accessory Configuration"
        case "APPLE_PAY":                       return "Apple Pay"
        case "DATA_PROTECTION":                 return "Data Protection"
        case "SIRIKIT":                         return "SiriKit"
        case "NETWORK_EXTENSIONS":              return "Network Extensions"
        case "MULTIPATH":                       return "Multipath"
        case "HOT_SPOT":                        return "Hotspot"
        case "NFC_TAG_READING":                 return "NFC Tag Reading"
        case "CLASSKIT":                        return "ClassKit"
        case "AUTOFILL_CREDENTIAL_PROVIDER":    return "AutoFill Credential Provider"
        case "ACCESS_WIFI_INFORMATION":         return "Access Wi-Fi Information"
        case "NETWORK_CUSTOM_PROTOCOL":         return "Network Custom Protocol"
        case "COREMEDIA_HLS_LOW_LATENCY":       return "Low Latency HLS"
        case "SYSTEM_EXTENSION_INSTALL":        return "System Extension"
        case "USER_MANAGEMENT":                 return "User Management"
        case "APPLE_ID_AUTH":                   return "Sign in with Apple"
        default:                                return capabilityType
        }
    }
}
