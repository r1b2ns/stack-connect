import Foundation

/// Actions the regular-width Version Detail puts in its toolbar (the compact
/// layout keeps them in the bottom action bar). Same rules as the bottom bar,
/// plus Resume for a paused phased release (on iPhone it lives in the sheet).
enum VersionDetailPrimaryAction: String, CaseIterable, Identifiable {
    case submitForReview
    case reject
    case release
    case cancelReview
    case cancelSubmission
    case pausePhasedRelease
    case resumePhasedRelease
    case completePhasedRelease

    var id: String { rawValue }

    var title: String {
        switch self {
        case .submitForReview:       return String(localized: "Submit for Review")
        case .reject:                return String(localized: "Reject")
        case .release:               return String(localized: "Release")
        case .cancelReview:          return String(localized: "Cancel Review")
        case .cancelSubmission:      return String(localized: "Cancel Submission")
        case .pausePhasedRelease:    return String(localized: "Pause")
        case .resumePhasedRelease:   return String(localized: "Resume")
        case .completePhasedRelease: return String(localized: "Release to All Users")
        }
    }

    var systemImage: String {
        switch self {
        case .submitForReview:       return "paperplane.fill"
        case .reject:                return "xmark.circle"
        case .release:               return "arrow.up.circle.fill"
        case .cancelReview:          return "xmark.circle"
        case .cancelSubmission:      return "xmark.circle"
        case .pausePhasedRelease:    return "pause.circle"
        case .resumePhasedRelease:   return "play.circle"
        case .completePhasedRelease: return "person.3.fill"
        }
    }

    /// The prominent action of a state (shown as the bordered-prominent button).
    var isProminent: Bool {
        switch self {
        case .submitForReview, .release, .completePhasedRelease: return true
        default: return false
        }
    }

    var isDestructive: Bool {
        switch self {
        case .reject, .cancelReview, .cancelSubmission: return true
        default: return false
        }
    }

    /// The actions available for a version, in toolbar order (prominent last).
    static func actions(
        state: AppStoreState?,
        phasedState: PhasedReleaseStatus?,
        canEdit: Bool,
        canDelete: Bool
    ) -> [VersionDetailPrimaryAction] {
        switch state {
        case .prepareForSubmission, .developerRejected:
            return canEdit ? [.submitForReview] : []
        case .pendingDeveloperRelease:
            var actions: [VersionDetailPrimaryAction] = []
            if canDelete { actions.append(.reject) }
            if canEdit { actions.append(.release) }
            return actions
        case .inReview, .waitingForReview:
            return canEdit ? [.cancelReview] : []
        case .readyForReview:
            return canEdit ? [.cancelSubmission] : []
        case .readyForSale:
            guard canEdit else { return [] }
            switch phasedState {
            case .active: return [.pausePhasedRelease, .completePhasedRelease]
            case .paused: return [.resumePhasedRelease, .completePhasedRelease]
            default:      return []
            }
        default:
            return []
        }
    }
}
