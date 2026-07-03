import Foundation

/// A requirement that must be satisfied before a version can be submitted for
/// App Store review. When missing, submission is blocked and the user is shown
/// an error listing the outstanding items.
enum PreSubmitRequirement: String, CaseIterable, Identifiable {
    case build
    case whatsNew
    case screenshots
    case demoAccount

    var id: String { rawValue }

    /// Human-readable reason shown in the "what's missing" error alert.
    var message: String {
        switch self {
        case .build:       return String(localized: "No build selected")
        case .whatsNew:    return String(localized: "\"What's New\" is empty")
        case .screenshots: return String(localized: "No screenshots uploaded")
        case .demoAccount: return String(localized: "A demo account is required but not filled in")
        }
    }
}

/// A read-only snapshot of everything shown in the pre-submit checklist bottom
/// sheet plus the data needed to validate a submission. Pure value type —
/// `make(...)` derives every flag so the validation logic is trivially testable.
struct PreSubmitChecklist: Equatable {
    /// Display string for the attached build, e.g. "3.1.0(1232)". `nil` when none.
    var buildNumber: String?
    var hasBuild: Bool
    var whatsNewFilled: Bool
    var marketingVersion: String?
    var isDemoAccountRequired: Bool
    var demoAccountFilled: Bool
    var releaseType: VersionReleaseType
    var phasedReleaseEnabled: Bool
    var hasScreenshots: Bool

    /// The demo-account row is satisfied when it isn't required, or when it is
    /// required and both name and password are present.
    var demoAccountSatisfied: Bool {
        !isDemoAccountRequired || demoAccountFilled
    }

    /// Requirements that are currently NOT satisfied. Order is stable so the
    /// error message reads consistently.
    var missingRequirements: [PreSubmitRequirement] {
        var missing: [PreSubmitRequirement] = []
        if !hasBuild { missing.append(.build) }
        if !whatsNewFilled { missing.append(.whatsNew) }
        if !hasScreenshots { missing.append(.screenshots) }
        if isDemoAccountRequired && !demoAccountFilled { missing.append(.demoAccount) }
        return missing
    }

    var isValid: Bool { missingRequirements.isEmpty }

    /// A single localized, multi-line message describing what's missing, or `nil`
    /// when the version is ready to submit.
    var validationMessage: String? {
        let missing = missingRequirements
        guard !missing.isEmpty else { return nil }
        let header = String(localized: "This version can't be submitted for review yet. Please resolve the following:")
        let lines = missing.map { "•  \($0.message)" }
        return ([header] + lines).joined(separator: "\n")
    }
}

extension PreSubmitChecklist {

    /// Builds a checklist from the raw App Store Connect data. `hasScreenshots` is
    /// passed in pre-computed because it requires per-localization fetches that the
    /// loader resolves; everything else is derived here.
    static func make(
        version: AppStoreVersionModel,
        build: BuildModel?,
        localizations: [AppStoreLocalizationModel],
        reviewDetail: AppReviewDetailModel?,
        phasedRelease: PhasedReleaseModel?,
        hasScreenshots: Bool
    ) -> PreSubmitChecklist {
        let whatsNewFilled = localizations.contains {
            !($0.whatsNew ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let demoRequired = reviewDetail?.isDemoAccountRequired ?? false
        let demoName = (reviewDetail?.demoAccountName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let demoPassword = (reviewDetail?.demoAccountPassword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let demoFilled = !demoName.isEmpty && !demoPassword.isEmpty

        let releaseType: VersionReleaseType
        switch version.releaseType {
        case "AFTER_APPROVAL": releaseType = .afterApproval
        case "SCHEDULED":      releaseType = .scheduled
        default:               releaseType = .manual
        }

        // A phased-release resource existing at all (even INACTIVE, before the
        // version ships) means the developer opted into a phased rollout.
        let phasedEnabled = phasedRelease != nil

        return PreSubmitChecklist(
            buildNumber: build?.displayVersion,
            hasBuild: build != nil,
            whatsNewFilled: whatsNewFilled,
            marketingVersion: version.versionString,
            isDemoAccountRequired: demoRequired,
            demoAccountFilled: demoFilled,
            releaseType: releaseType,
            phasedReleaseEnabled: phasedEnabled,
            hasScreenshots: hasScreenshots
        )
    }
}
