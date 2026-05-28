import Foundation

struct BundleIdentifierModel: Identifiable, Hashable, Codable {
    let id: String
    let identifier: String
    let name: String
    let platform: String
    let seedId: String?

    var platformDisplayName: String {
        switch platform {
        case "IOS":       return String(localized: "iOS, tvOS, watchOS, visionOS")
        case "MAC_OS":    return String(localized: "macOS")
        case "UNIVERSAL": return String(localized: "Universal")
        case "SERVICES":  return String(localized: "Services")
        default:          return platform
        }
    }
}
