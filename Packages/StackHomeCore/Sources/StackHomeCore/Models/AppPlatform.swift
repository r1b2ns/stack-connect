import Foundation

/// App Store platform identifier. Foundation-pure: `icon` is a raw SF Symbol
/// *name* token (consumed by `Image(systemName:)` on iOS, substituted on
/// Windows). Migrated into StackHomeCore so the Foundation-pure
/// `AppleAccountSyncing` protocol (and the value models it references) can live
/// in core without any platform/SDK dependency.
public enum AppPlatform: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case ios = "IOS"
    case macOs = "MAC_OS"
    case tvOs = "TV_OS"
    case visionOs = "VISION_OS"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ios:      return "iOS"
        case .macOs:    return "macOS"
        case .tvOs:     return "tvOS"
        case .visionOs: return "visionOS"
        }
    }

    /// Raw SF Symbol name token. Platform UI maps this to its own icon
    /// (`Image(systemName:)` on iOS; a glyph/text substitute on Windows).
    public var icon: String {
        switch self {
        case .ios:      return "iphone"
        case .macOs:    return "macbook"
        case .tvOs:     return "appletv"
        case .visionOs: return "visionpro"
        }
    }
}
