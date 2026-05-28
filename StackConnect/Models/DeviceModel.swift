import Foundation

struct DeviceModel: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let udid: String?
    let platform: String?
    let deviceClass: String?
    let model: String?
    let status: String
    let addedDate: Date?

    var isEnabled: Bool { status == "ENABLED" }

    var platformDisplayName: String {
        switch platform {
        case "IOS":       return String(localized: "iOS, tvOS, watchOS, visionOS")
        case "MAC_OS":    return String(localized: "macOS")
        case "UNIVERSAL": return String(localized: "Universal")
        case .some(let raw): return raw
        case .none:       return "—"
        }
    }

    var deviceClassDisplayName: String {
        switch deviceClass {
        case "IPHONE":            return String(localized: "iPhone")
        case "IPAD":              return String(localized: "iPad")
        case "IPOD":              return String(localized: "iPod")
        case "APPLE_TV":          return String(localized: "Apple TV")
        case "APPLE_WATCH":       return String(localized: "Apple Watch")
        case "APPLE_VISION_PRO":  return String(localized: "Apple Vision Pro")
        case "MAC":               return String(localized: "Mac")
        case .some(let raw):      return raw
        case .none:               return "—"
        }
    }
}
