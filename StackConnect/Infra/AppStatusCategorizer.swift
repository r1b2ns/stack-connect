import Foundation

enum AppStatusCategorizer {

    static func categorize(
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
    static func inReviewEntries(_ apps: [AppModel]) -> [AppModel] {
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
