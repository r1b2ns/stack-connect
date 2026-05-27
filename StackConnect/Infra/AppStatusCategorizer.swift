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
}
