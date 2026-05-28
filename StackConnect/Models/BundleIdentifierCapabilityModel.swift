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
        case "FONT_INSTALLATION":               return "Font Installation"
        case "CARPLAY_CHARGING":                return "CarPlay (Charging)"
        case "CARPLAY_AUDIO":                   return "CarPlay (Audio)"
        case "CARPLAY_COMMUNICATION":           return "CarPlay (Communication)"
        case "CARPLAY_QUICK_ORDERING":          return "CarPlay (Quick Ordering)"
        case "CARPLAY_DRIVING_TASK":            return "CarPlay (Driving Task)"
        case "CARPLAY_PARKING":                 return "CarPlay (Parking)"
        case "CARPLAY_PLAYABLE_CONTENT":        return "CarPlay (Playable Content)"
        case "FAMILY_CONTROLS":                 return "Family Controls"
        case "DRIVERKIT":                       return "DriverKit"
        case "FILE_PROVIDER_TESTING_MODE":      return "File Provider Testing Mode"
        case "GROUP_ACTIVITIES":                return "Group Activities"
        case "SHARED_WITH_YOU":                 return "Shared with You"
        case "EXTENDED_VIRTUAL_ADDRESSING":     return "Extended Virtual Addressing"
        case "INCREASED_MEMORY_LIMIT":          return "Increased Memory Limit"
        case "WEATHERKIT":                      return "WeatherKit"
        case "MUSICKIT":                        return "MusicKit"
        case "SHALLOW_DEPTH_AND_PRESSURE":      return "Shallow Depth and Pressure"
        case "JOURNALING_SUGGESTIONS":          return "Journaling Suggestions"
        case "MATTER":                          return "Matter"
        case "MEDIA_DEVICE_DISCOVERY":          return "Media Device Discovery"
        case "ON_DEMAND_INSTALL_CAPABLE":       return "On Demand Resources / App Clips"
        case "BACKGROUND_ASSETS":               return "Background Assets"
        case "MANAGED_APP_INSTALLATION":        return "Managed App Installation"
        default:
            // Fallback: turn `SOME_NEW_CAPABILITY_TYPE` into `Some New Capability Type`.
            return capabilityType
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
}
