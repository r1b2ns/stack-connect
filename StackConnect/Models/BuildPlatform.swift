import Foundation

enum BuildPlatform {
    static let allKnown: [String] = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]

    static func icon(for platform: String?) -> String {
        switch platform {
        case "IOS":        return "iphone"
        case "MAC_OS":     return "laptopcomputer"
        case "TV_OS":      return "appletv"
        case "VISION_OS":  return "visionpro"
        default:           return "questionmark.app.dashed"
        }
    }

    static func label(for platform: String?) -> String {
        switch platform {
        case "IOS":        return "iOS"
        case "MAC_OS":     return "macOS"
        case "TV_OS":      return "tvOS"
        case "VISION_OS":  return "visionOS"
        default:           return String(localized: "Other")
        }
    }

    /// Stable sort order: iOS, macOS, tvOS, visionOS, unknown.
    static func sortOrder(_ platform: String?) -> Int {
        switch platform {
        case "IOS":        return 0
        case "MAC_OS":     return 1
        case "TV_OS":      return 2
        case "VISION_OS":  return 3
        default:           return 99
        }
    }
}
