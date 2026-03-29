import Foundation

enum AppPlatform: String, Codable, CaseIterable, Hashable, Identifiable {
    case ios = "IOS"
    case macOs = "MAC_OS"
    case tvOs = "TV_OS"
    case visionOs = "VISION_OS"

    var id: String { rawValue }

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
