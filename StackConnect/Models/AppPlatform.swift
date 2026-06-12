import Foundation

enum AppPlatform: String, Codable, CaseIterable, Hashable, Identifiable {
    case ios = "IOS"
    case macOs = "MAC_OS"
    case tvOs = "TV_OS"
    case visionOs = "VISION_OS"

    var id: String { rawValue }

    /// Builds an `AppPlatform` from a raw platform string, tolerating the
    /// alias spellings the App Store Connect API can return
    /// (e.g. `TVOS`/`TV_OS`, `MACOS`/`MAC_OS`, `XROS`/`VISION_OS`).
    static func from(_ raw: String) -> AppPlatform? {
        switch raw.uppercased() {
        case "IOS":                 return .ios
        case "MAC_OS", "MACOS":     return .macOs
        case "TV_OS", "TVOS":       return .tvOs
        case "VISION_OS", "XROS":   return .visionOs
        default:                    return nil
        }
    }

    var displayName: String {
        switch self {
        case .ios:      return "iOS"
        case .macOs:    return "macOS"
        case .tvOs:     return "tvOS"
        case .visionOs: return "visionOS"
        }
    }

    var icon: String {
        switch self {
        case .ios:      return "iphone"
        case .macOs:    return "macbook"
        case .tvOs:     return "appletv"
        case .visionOs: return "visionpro"
        }
    }
}
