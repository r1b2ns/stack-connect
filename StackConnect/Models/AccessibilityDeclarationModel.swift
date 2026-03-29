import Foundation

struct AccessibilityDeclarationModel: Codable, Identifiable, Hashable {
    let id: String
    var deviceFamily: String
    var state: String?
    var supportsAudioDescriptions: Bool
    var supportsCaptions: Bool
    var supportsDarkInterface: Bool
    var supportsDifferentiateWithoutColor: Bool
    var supportsLargerText: Bool
    var supportsReducedMotion: Bool
    var supportsSufficientContrast: Bool
    var supportsVoiceControl: Bool
    var supportsVoiceover: Bool

    var deviceFamilyDisplayName: String {
        switch deviceFamily {
        case "IPHONE":      return "iPhone"
        case "IPAD":        return "iPad"
        case "APPLE_TV":    return "Apple TV"
        case "APPLE_WATCH": return "Apple Watch"
        case "MAC":         return "Mac"
        case "VISION":      return "Apple Vision Pro"
        default:            return deviceFamily
        }
    }

    var deviceFamilyIcon: String {
        switch deviceFamily {
        case "IPHONE":      return "iphone"
        case "IPAD":        return "ipad"
        case "APPLE_TV":    return "appletv"
        case "APPLE_WATCH": return "applewatch"
        case "MAC":         return "macbook"
        case "VISION":      return "visionpro"
        default:            return "rectangle"
        }
    }

    var stateDisplayName: String {
        switch state {
        case "DRAFT":     return String(localized: "Draft")
        case "PUBLISHED": return String(localized: "Published")
        case "REPLACED":  return String(localized: "Replaced")
        default:          return state ?? "–"
        }
    }

    var stateColor: AppStoreStateColor {
        switch state {
        case "PUBLISHED": return .green
        case "DRAFT":     return .orange
        case "REPLACED":  return .gray
        default:          return .gray
        }
    }

    var supportedFeaturesCount: Int {
        [supportsAudioDescriptions, supportsCaptions, supportsDarkInterface,
         supportsDifferentiateWithoutColor, supportsLargerText, supportsReducedMotion,
         supportsSufficientContrast, supportsVoiceControl, supportsVoiceover]
            .filter { $0 }.count
    }
}
