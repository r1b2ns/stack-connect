import Foundation

/// A change the user can make to one Google Play release (plan R8).
enum GooglePlayReleaseAction: Hashable, Sendable {
    /// Start serving a draft: a staged rollout where the track supports one,
    /// otherwise a release to everyone.
    case rollOut
    /// Raise the fraction of a running staged rollout.
    case increaseRollout
    /// Stop serving a running rollout to new users.
    case halt
    /// Restart a halted rollout.
    case resume
    /// Serve the release to everyone (`completed`).
    case releaseToAll
    /// Copy a completed release to another track.
    case promote
}

/// Which actions a release offers (plan R8), in one pure, testable place so the
/// release detail's bottom bar, the swipe actions and any later entry point
/// agree:
///
/// - `draft` → Roll out
/// - `inProgress` → Increase rollout (staged tracks, fraction below 100%) /
///   Halt / Release to all
/// - `halted` → Resume / Release to all
/// - `completed` → Promote (not from production: there is no track above it)
///
/// Staged rollout exists on production and open testing only. A release Google
/// did not approve offers nothing: it has to be fixed in a new release. Unknown
/// statuses offer nothing either (fail closed).
enum GooglePlayReleaseActions {

    /// Tracks where Google supports a staged (percentage) rollout.
    static func supportsStagedRollout(_ kind: GooglePlayTrackKind) -> Bool {
        switch kind {
        case .production, .openTesting: return true
        case .closedTesting, .internalTesting, .custom: return false
        }
    }

    static func actions(
        trackKind: GooglePlayTrackKind,
        status: GooglePlayReleaseStatus,
        userFraction: Double?,
        lifecycleState: GooglePlayReleaseLifecycleState?
    ) -> [GooglePlayReleaseAction] {
        if lifecycleState == .notApproved {
            return []
        }
        switch status {
        case .draft:
            return [.rollOut]
        case .inProgress:
            let canIncrease = supportsStagedRollout(trackKind) && (userFraction.map { $0 < 1 } ?? false)
            return (canIncrease ? [.increaseRollout] : []) + [.halt, .releaseToAll]
        case .halted:
            return [.resume, .releaseToAll]
        case .completed:
            return trackKind == .production ? [] : [.promote]
        case .unknown:
            return []
        }
    }

    /// Convenience for a track release plus its summary's lifecycle state.
    static func actions(
        for release: GooglePlayReleaseModel,
        on trackKind: GooglePlayTrackKind,
        lifecycleState: GooglePlayReleaseLifecycleState?
    ) -> [GooglePlayReleaseAction] {
        actions(trackKind: trackKind, status: release.status, userFraction: release.userFraction, lifecycleState: lifecycleState)
    }
}
