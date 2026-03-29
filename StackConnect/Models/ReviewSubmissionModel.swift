import Foundation

struct ReviewSubmissionModel: Codable, Identifiable, Hashable {
    let id: String
    var appId: String
    var platform: String?
    var submittedDate: Date?
    var state: String?
    var versionString: String?
    var versionId: String?
    var submittedByName: String?
    var submittedByEmail: String?

    var stateDisplayName: String {
        switch state {
        case "READY_FOR_REVIEW":   return String(localized: "Ready for Review")
        case "WAITING_FOR_REVIEW": return String(localized: "Waiting for Review")
        case "IN_REVIEW":          return String(localized: "In Review")
        case "UNRESOLVED_ISSUES":  return String(localized: "Unresolved Issues")
        case "CANCELING":          return String(localized: "Canceling")
        case "COMPLETING":         return String(localized: "Completing")
        case "COMPLETE":           return String(localized: "Complete")
        default:                   return state ?? "–"
        }
    }

    var stateColor: AppStoreStateColor {
        switch state {
        case "IN_REVIEW", "COMPLETING": return .blue
        case "WAITING_FOR_REVIEW":      return .yellow
        case "COMPLETE":                return .green
        case "UNRESOLVED_ISSUES":       return .red
        case "READY_FOR_REVIEW":        return .orange
        default:                        return .gray
        }
    }

    var platformDisplayName: String {
        switch platform {
        case "IOS":       return "iOS"
        case "MAC_OS":    return "macOS"
        case "TV_OS":     return "tvOS"
        case "VISION_OS": return "visionOS"
        default:          return platform ?? "–"
        }
    }
}
