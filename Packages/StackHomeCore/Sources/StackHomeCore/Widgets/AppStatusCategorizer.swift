import Foundation

/// Pure categorization of apps into the "In Review" and "Awaiting Release"
/// buckets that back the Home widgets.
///
/// Foundation-pure (US-010): no UIKit/SwiftUI/WidgetKit imports. Shared by the
/// iOS app and the Windows port. Implements the widget semantics for In Review
/// (TC-033) and Awaiting Release phased grouping (TC-034).
public enum AppStatusCategorizer {

    /// Splits apps into the In Review and Awaiting Release buckets.
    ///
    /// - `readyForSale` apps only count as awaiting release when they have an
    ///   *active* or *paused* phased release (TC-034); a *complete* phased
    ///   release is ignored.
    public static func categorize(
        _ apps: [AppModel],
        phasedByAppId: [String: PhasedReleaseModel]
    ) -> (inReview: [AppModel], awaitingRelease: [AppModel]) {
        var inReview: [AppModel] = []
        var awaiting: [AppModel] = []
        for app in apps {
            guard let state = app.appStoreState else { continue }
            switch state {
            case .waitingForReview, .inReview, .readyForReview,
                 .pendingAppleRelease, .processingForAppStore,
                 .rejected, .metadataRejected, .invalidBinary:
                inReview.append(app)
            case .pendingDeveloperRelease:
                awaiting.append(app)
            case .readyForSale:
                if let phased = phasedByAppId[app.id],
                   phased.state == .active || phased.state == .paused {
                    awaiting.append(app)
                }
            default:
                break
            }
        }
        return (inReview, awaiting)
    }

    /// Expands apps into "In Review" entries per platform: an app shipping both,
    /// say, an iOS version in review and a tvOS version with an invalid binary
    /// yields two entries. Each entry is a copy of the app with `appStoreState`,
    /// `platform` and `versionString` set to that platform's values. Falls back
    /// to the app's primary state when no per-platform data is available.
    public static func inReviewEntries(_ apps: [AppModel]) -> [AppModel] {
        var result: [AppModel] = []
        for app in apps {
            if let platformVersions = app.platformVersions, !platformVersions.isEmpty {
                for version in platformVersions {
                    guard let state = version.appStoreState, state.isInReviewBucket else { continue }
                    var entry = app
                    entry.appStoreState = state
                    entry.platform = version.platform
                    entry.versionString = version.versionString
                    result.append(entry)
                }
            } else if let state = app.appStoreState, state.isInReviewBucket {
                result.append(app)
            }
        }
        return result
    }
}
