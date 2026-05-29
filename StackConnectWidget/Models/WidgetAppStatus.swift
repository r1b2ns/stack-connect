import SwiftUI

// MARK: - App Store State (raw-string mapping)
//
// The widget decodes `appStoreState` as the raw API string. These helpers mirror
// the app's `AppStoreState` display name + color without importing the app module.

enum WidgetAppStatus {

    static func displayName(for raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case "ACCEPTED":                    return String(localized: "Accepted")
        case "DEVELOPER_REMOVED_FROM_SALE": return String(localized: "Removed from Sale")
        case "DEVELOPER_REJECTED":          return String(localized: "Developer Rejected")
        case "IN_REVIEW":                   return String(localized: "In Review")
        case "INVALID_BINARY":              return String(localized: "Invalid Binary")
        case "METADATA_REJECTED":           return String(localized: "Metadata Rejected")
        case "PENDING_APPLE_RELEASE":       return String(localized: "Pending Apple Release")
        case "PENDING_CONTRACT":            return String(localized: "Pending Contract")
        case "PENDING_DEVELOPER_RELEASE":   return String(localized: "Pending Developer Release")
        case "PREPARE_FOR_SUBMISSION":      return String(localized: "Prepare for Submission")
        case "PREORDER_READY_FOR_SALE":     return String(localized: "Pre-Order Ready for Sale")
        case "PROCESSING_FOR_APP_STORE":    return String(localized: "Processing for App Store")
        case "READY_FOR_REVIEW":            return String(localized: "Ready for Review")
        case "READY_FOR_SALE":              return String(localized: "Ready for Sale")
        case "REJECTED":                    return String(localized: "Rejected")
        case "REMOVED_FROM_SALE":           return String(localized: "Removed from Sale")
        case "WAITING_FOR_EXPORT_COMPLIANCE": return String(localized: "Waiting for Export Compliance")
        case "WAITING_FOR_REVIEW":          return String(localized: "Waiting for Review")
        case "REPLACED_WITH_NEW_VERSION":   return String(localized: "Replaced with New Version")
        case "NOT_APPLICABLE":              return String(localized: "Not Applicable")
        default:                            return raw
        }
    }

    static func color(for raw: String?) -> Color {
        switch raw {
        case "READY_FOR_SALE", "PREORDER_READY_FOR_SALE", "ACCEPTED":
            return .green
        case "IN_REVIEW", "WAITING_FOR_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE":
            return .orange
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY":
            return .red
        case "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW":
            return .blue
        case "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE", "PENDING_CONTRACT", "PROCESSING_FOR_APP_STORE":
            return .yellow
        default:
            return .gray
        }
    }

    /// True when the state belongs in the "In Review" widget.
    static func isInReview(_ raw: String?) -> Bool {
        switch raw {
        case "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW",
             "PENDING_APPLE_RELEASE", "PROCESSING_FOR_APP_STORE",
             "REJECTED", "METADATA_REJECTED", "INVALID_BINARY":
            return true
        default:
            return false
        }
    }
}

// MARK: - Platform (raw-string mapping)
//
// Mirrors the app's `AppPlatform` icon/displayName without importing the app
// module. `order` is used to group In Review apps by platform.

enum WidgetPlatform {

    static let order = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]

    static func icon(for raw: String?) -> String? {
        switch raw {
        case "IOS":       return "iphone"
        case "MAC_OS":    return "macbook"
        case "TV_OS":     return "appletv"
        case "VISION_OS": return "visionpro"
        default:          return nil
        }
    }

    static func displayName(for raw: String?) -> String? {
        switch raw {
        case "IOS":       return "iOS"
        case "MAC_OS":    return "macOS"
        case "TV_OS":     return "tvOS"
        case "VISION_OS": return "visionOS"
        default:          return raw
        }
    }
}
