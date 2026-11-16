import Foundation

/// A release change the user asked for and has not confirmed yet (plan R4).
/// Carries everything the confirmation and the success toast say.
struct GooglePlayPendingWrite: Identifiable, Hashable {

    let id = UUID()
    /// Raw track the change is committed on.
    let track: String
    let change: GooglePlayReleaseChange
    /// Short name of the release ("4.2.0").
    let releaseTitle: String

    var trackKind: GooglePlayTrackKind { GooglePlayTrackKind(track: track) }

    /// Said on every confirmation: a write commits an edit (R4).
    static var editWarning: String {
        String(localized: "This opens a Play edit and commits it. Any edit this service account has open for the app elsewhere (for example a CI upload) is cancelled.")
    }

    var title: String {
        switch change {
        case .setRollout:     return String(localized: "Update Staged Rollout?")
        case .halt:           return String(localized: "Halt Rollout?")
        case .resume:         return String(localized: "Resume Rollout?")
        case .complete:       return String(localized: "Release to All Users?")
        case .updateMetadata: return String(localized: "Save Release Details?")
        case .create:         return String(localized: "Create Release?")
        case .promote:        return String(localized: "Promote Release?")
        }
    }

    /// What happens, then the edit warning.
    var message: String {
        "\(summary)\n\n\(Self.editWarning)"
    }

    var summary: String {
        let track = trackKind.displayName
        switch change {
        case .setRollout(_, let fraction):
            return String(localized: "\(track) will serve \(releaseTitle) to \(Self.percent(fraction)) of users.",
                          comment: "Google Play rollout confirmation. Arguments: track name, release name, percentage.")
        case .halt:
            return String(localized: "New users on \(track) stop getting \(releaseTitle). Users who already updated keep it.",
                          comment: "Google Play halt confirmation. Arguments: track name, release name.")
        case .resume:
            return String(localized: "\(track) starts serving \(releaseTitle) to new users again.",
                          comment: "Google Play resume confirmation. Arguments: track name, release name.")
        case .complete:
            return String(localized: "\(track) will serve \(releaseTitle) to every user.",
                          comment: "Google Play complete rollout confirmation. Arguments: track name, release name.")
        case .updateMetadata:
            return String(localized: "The name, release notes and update priority of \(releaseTitle) on \(track) are replaced.",
                          comment: "Google Play metadata confirmation. Arguments: release name, track name.")
        case .create(let release):
            return String(localized: "\(releaseTitle) is added to \(track) (\(Self.statusText(release.status))).",
                          comment: "Google Play new release confirmation. Arguments: release name, track name, how it is served.")
        case .promote(let fromTrack, _, let status, _, _, _):
            return String(localized: "\(releaseTitle) is copied from \(GooglePlayTrackKind(track: fromTrack).displayName) to \(track) (\(Self.statusText(status))).",
                          comment: "Google Play promote confirmation. Arguments: release name, source track, target track, how it is served.")
        }
    }

    var confirmLabel: String {
        switch change {
        case .setRollout:     return String(localized: "Update Rollout")
        case .halt:           return String(localized: "Halt")
        case .resume:         return String(localized: "Resume")
        case .complete:       return String(localized: "Release to All")
        case .updateMetadata: return String(localized: "Save")
        case .create:         return String(localized: "Create")
        case .promote:        return String(localized: "Promote")
        }
    }

    var isDestructive: Bool {
        if case .halt = change { return true }
        return false
    }

    /// Toast after a successful commit.
    var successMessage: String {
        switch change {
        case .setRollout(_, let fraction):
            return String(localized: "Rollout set to \(Self.percent(fraction))", comment: "Toast. Argument: a percentage.")
        case .halt:           return String(localized: "Rollout halted")
        case .resume:         return String(localized: "Rollout resumed")
        case .complete:       return String(localized: "Released to all users")
        case .updateMetadata: return String(localized: "Release details saved")
        case .create:         return String(localized: "Release created")
        case .promote:        return String(localized: "Release promoted")
        }
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0...2)))
    }

    static func statusText(_ status: GooglePlayNewReleaseStatus) -> String {
        switch status {
        case .draft:                        return String(localized: "draft")
        case .inProgress(let userFraction): return String(localized: "\(percent(userFraction)) of users", comment: "Argument: a percentage.")
        case .completed:                    return String(localized: "all users")
        }
    }
}
