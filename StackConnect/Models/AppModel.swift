import Foundation

struct AppModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let bundleId: String
    let platform: String?
    let accountId: String
    var iconUrl: String?
    var appStoreState: AppStoreState?
    var versionString: String?
    var lastModifiedDate: Date?
    var isArchived: Bool
    var isFavorite: Bool
    var hasReviewPending: Bool

    init(
        id: String,
        name: String,
        bundleId: String,
        platform: String? = nil,
        accountId: String,
        iconUrl: String? = nil,
        appStoreState: AppStoreState? = nil,
        versionString: String? = nil,
        lastModifiedDate: Date? = nil,
        isArchived: Bool = false,
        isFavorite: Bool = false,
        hasReviewPending: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.platform = platform
        self.accountId = accountId
        self.iconUrl = iconUrl
        self.appStoreState = appStoreState
        self.versionString = versionString
        self.lastModifiedDate = lastModifiedDate
        self.isArchived = isArchived
        self.isFavorite = isFavorite
        self.hasReviewPending = hasReviewPending
    }
}

// MARK: - AppStoreState

enum AppStoreState: String, Codable, Hashable {
    case accepted = "ACCEPTED"
    case developerRemovedFromSale = "DEVELOPER_REMOVED_FROM_SALE"
    case developerRejected = "DEVELOPER_REJECTED"
    case inReview = "IN_REVIEW"
    case invalidBinary = "INVALID_BINARY"
    case metadataRejected = "METADATA_REJECTED"
    case pendingAppleRelease = "PENDING_APPLE_RELEASE"
    case pendingContract = "PENDING_CONTRACT"
    case pendingDeveloperRelease = "PENDING_DEVELOPER_RELEASE"
    case prepareForSubmission = "PREPARE_FOR_SUBMISSION"
    case preorderReadyForSale = "PREORDER_READY_FOR_SALE"
    case processingForAppStore = "PROCESSING_FOR_APP_STORE"
    case readyForReview = "READY_FOR_REVIEW"
    case readyForSale = "READY_FOR_SALE"
    case rejected = "REJECTED"
    case removedFromSale = "REMOVED_FROM_SALE"
    case waitingForExportCompliance = "WAITING_FOR_EXPORT_COMPLIANCE"
    case waitingForReview = "WAITING_FOR_REVIEW"
    case replacedWithNewVersion = "REPLACED_WITH_NEW_VERSION"
    case notApplicable = "NOT_APPLICABLE"

    var displayName: String {
        switch self {
        case .accepted:                  return String(localized: "Accepted")
        case .developerRemovedFromSale:  return String(localized: "Removed from Sale")
        case .developerRejected:         return String(localized: "Developer Rejected")
        case .inReview:                  return String(localized: "In Review")
        case .invalidBinary:             return String(localized: "Invalid Binary")
        case .metadataRejected:          return String(localized: "Metadata Rejected")
        case .pendingAppleRelease:       return String(localized: "Pending Apple Release")
        case .pendingContract:           return String(localized: "Pending Contract")
        case .pendingDeveloperRelease:   return String(localized: "Pending Developer Release")
        case .prepareForSubmission:      return String(localized: "Prepare for Submission")
        case .preorderReadyForSale:      return String(localized: "Pre-Order Ready for Sale")
        case .processingForAppStore:     return String(localized: "Processing for App Store")
        case .readyForReview:            return String(localized: "Ready for Review")
        case .readyForSale:              return String(localized: "Ready for Sale")
        case .rejected:                  return String(localized: "Rejected")
        case .removedFromSale:           return String(localized: "Removed from Sale")
        case .waitingForExportCompliance: return String(localized: "Waiting for Export Compliance")
        case .waitingForReview:          return String(localized: "Waiting for Review")
        case .replacedWithNewVersion:    return String(localized: "Replaced with New Version")
        case .notApplicable:             return String(localized: "Not Applicable")
        }
    }

    /// Whether this state indicates the app has a pending review action (waiting, in review, rejected, etc.)
    var isReviewPending: Bool {
        switch self {
        case .waitingForReview, .inReview, .rejected, .metadataRejected,
             .invalidBinary, .pendingDeveloperRelease, .pendingAppleRelease:
            return true
        default:
            return false
        }
    }

    var color: AppStoreStateColor {
        switch self {
        case .readyForSale, .preorderReadyForSale:
            return .green
        case .inReview, .waitingForReview, .waitingForExportCompliance:
            return .orange
        case .rejected, .metadataRejected, .invalidBinary:
            return .red
        case .developerRejected, .developerRemovedFromSale, .removedFromSale:
            return .gray
        case .prepareForSubmission, .readyForReview:
            return .blue
        case .pendingAppleRelease, .pendingDeveloperRelease, .pendingContract, .processingForAppStore:
            return .yellow
        case .accepted:
            return .green
        case .replacedWithNewVersion, .notApplicable:
            return .gray
        }
    }
}

enum AppStoreStateColor {
    case green, orange, red, gray, blue, yellow
}
