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

    /// Expands apps into "Awaiting Release" entries per platform, mirroring
    /// `inReviewEntries`. A version qualifies when its state is
    /// `pendingDeveloperRelease`, or when it is `readyForSale` AND has an
    /// active/paused phased release. Each entry is a copy of the app with
    /// `appStoreState`, `platform` and `versionString` set to that platform's
    /// values. Falls back to the app's primary state (using the app id as the
    /// phased-release lookup key) when no per-platform data is available.
    ///
    /// - Parameter phasedByVersionId: phased releases keyed by version id (matching
    ///   the `"phased.{versionId}"` storage scheme). The fallback path additionally
    ///   consults `app.id` so single-platform apps that predate per-version ids
    ///   still resolve their phased release.
    static func awaitingReleaseEntries(
        _ apps: [AppModel],
        phasedByVersionId: [String: PhasedReleaseModel]
    ) -> [AppModel] {
        var result: [AppModel] = []
        for app in apps {
            if let awaitingVersions = app.awaitingVersions {
                // Preferred path: `awaitingVersions` retains a still-phasing
                // `readyForSale` version even after a newer version has moved to
                // `prepareForSubmission`, so the rollout keeps showing here.
                for version in awaitingVersions {
                    if let entry = awaitingEntry(app: app, version: version, phasedByVersionId: phasedByVersionId) {
                        result.append(entry)
                    }
                }
            } else if let platformVersions = app.platformVersions, !platformVersions.isEmpty {
                // Legacy data (persisted before `awaitingVersions`): latest per platform.
                for version in platformVersions {
                    if let entry = awaitingEntry(app: app, version: version, phasedByVersionId: phasedByVersionId) {
                        result.append(entry)
                    }
                }
            } else if let state = app.appStoreState,
                      isAwaiting(state: state, phased: phasedByVersionId[app.id]) {
                result.append(app)
            }
        }
        return result
    }

    /// Builds an awaiting-release entry for a single per-platform version, or
    /// `nil` when that version isn't awaiting. The entry keeps the app's full
    /// `platformVersions` (so App Detail still shows every platform the app ships)
    /// and its `awaitingVersions`; its own `platform`/`versionString` identify
    /// which version this entry represents, so the widget resolves the exact
    /// phased release via `HomeWidgetDataLoader.phasedRelease(for:in:)` — an app
    /// can expose two versions for one platform (a phasing `readyForSale` one plus
    /// a newer prepared one).
    private static func awaitingEntry(
        app: AppModel,
        version: AppPlatformVersion,
        phasedByVersionId: [String: PhasedReleaseModel]
    ) -> AppModel? {
        guard let state = version.appStoreState,
              isAwaiting(state: state, phased: phasedByVersionId[version.id ?? ""])
        else { return nil }
        var entry = app
        entry.appStoreState = state
        entry.platform = version.platform
        entry.versionString = version.versionString
        // Awaiting rows show each platform's real icon (falling back to the app's
        // single icon). In Review rows intentionally keep the app icon.
        entry.iconUrl = version.iconUrl ?? app.iconUrl
        return entry
    }

    /// The awaiting-release decision used by `awaitingReleaseEntries`:
    /// `pendingDeveloperRelease` always awaits; `readyForSale` awaits only with an
    /// active/paused phased release.
    private static func isAwaiting(state: AppStoreState, phased: PhasedReleaseModel?) -> Bool {
        switch state {
        case .pendingDeveloperRelease:
            return true
        case .readyForSale:
            guard let phased else { return false }
            return phased.state == .active || phased.state == .paused
        default:
            return false
        }
    }
}
