import Foundation

/// An app bundle already uploaded to Google Play (`edits.bundles.list`), the
/// source of a new release. Google shares no upload date or version name.
struct GooglePlayBundleModel: Codable, Hashable, Identifiable, Sendable {
    /// Decimal string (Play's int64).
    let versionCode: String
    var sha256: String?

    var id: String { versionCode }

    /// Numeric version code for ordering and the "higher than live" guard.
    var versionCodeValue: Int64 { Int64(versionCode) ?? 0 }
}

/// What a new or promoted release does once committed.
enum GooglePlayNewReleaseStatus: Hashable, Sendable {
    /// Stays on the track, served to nobody.
    case draft
    /// Staged rollout to `userFraction` of users, in `(0, 1)`.
    case inProgress(userFraction: Double)
    /// Served to everyone.
    case completed
}

/// A release created from an uploaded bundle.
struct GooglePlayNewRelease: Hashable, Sendable {
    var versionCodes: [String]
    var name: String?
    var releaseNotes: [GooglePlayLocalizedTextModel]
    var status: GooglePlayNewReleaseStatus
    /// `0`–`5`; `nil` leaves Google's default.
    var inAppUpdatePriority: Int?
}

/// Release metadata to change; `nil` fields stay as they are.
struct GooglePlayReleaseMetadataUpdate: Hashable, Sendable {
    var name: String?
    var releaseNotes: [GooglePlayLocalizedTextModel]?
    var inAppUpdatePriority: Int?
}

/// One typed change to a Google Play track (plan R2). The core applies it
/// inside one edit on a fresh read of the track, so the app never sends a whole
/// track back. Releases are targeted by their version codes (R7).
enum GooglePlayReleaseChange: Hashable, Sendable {
    case setRollout(versionCodes: [String], userFraction: Double)
    case halt(versionCodes: [String])
    case resume(versionCodes: [String])
    case complete(versionCodes: [String])
    case updateMetadata(versionCodes: [String], update: GooglePlayReleaseMetadataUpdate)
    case create(GooglePlayNewRelease)
    /// Copies the release `versionCodes` of `fromTrack` onto the target track.
    /// `nil` name / notes / priority keep the source release's.
    case promote(
        fromTrack: String,
        versionCodes: [String],
        status: GooglePlayNewReleaseStatus,
        name: String?,
        releaseNotes: [GooglePlayLocalizedTextModel]?,
        inAppUpdatePriority: Int?
    )

    /// Version codes of the release the change targets or creates.
    var versionCodes: [String] {
        switch self {
        case .setRollout(let codes, _), .halt(let codes), .resume(let codes), .complete(let codes),
             .updateMetadata(let codes, _), .promote(_, let codes, _, _, _, _):
            return codes
        case .create(let release):
            return release.versionCodes
        }
    }

    /// Creating or promoting needs the `add` rule; the others `edit` (plan R5).
    var addsRelease: Bool {
        switch self {
        case .create, .promote: return true
        default:                return false
        }
    }
}

/// How Google treats a commit (`edits.commit` query parameters).
struct GooglePlayCommitOptions: Hashable, Sendable {

    /// What to do when another change of the app is already in review.
    enum ReviewInProgressBehavior: Hashable, CaseIterable, Sendable {
        /// `ERROR_IF_IN_REVIEW`: refuse the commit and report it.
        case stopAndReport
        /// `CANCEL_IN_REVIEW_AND_SUBMIT`: cancel that review and send everything.
        case cancelAndResubmit

        var displayName: String {
            switch self {
            case .stopAndReport:     return String(localized: "Stop and report")
            case .cancelAndResubmit: return String(localized: "Cancel review and resubmit")
            }
        }
    }

    /// Off sends `changesNotSentForReview=true`: the changes wait in Play
    /// Console until someone sends them for review there.
    var sendForReview: Bool = true
    var reviewInProgress: ReviewInProgressBehavior = .stopAndReport

    static let `default` = GooglePlayCommitOptions()
}
