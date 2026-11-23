import Foundation

@MainActor
enum HomeWidgetRegistry {

    static let defaultConfigurations: [HomeWidgetConfiguration] = []

    static func make(
        for configuration: HomeWidgetConfiguration,
        storage: PersistentStorable,
        featureFlags: FeatureFlags = .shared
    ) -> any HomeWidget {
        switch configuration.kind {
        case .inReview:
            return InReviewWidget(configuration: configuration, storage: storage, featureFlags: featureFlags)
        case .awaitingRelease:
            return AwaitingReleaseWidget(configuration: configuration, storage: storage, featureFlags: featureFlags)
        case .recentReviews:
            return RecentReviewsWidget(configuration: configuration, storage: storage, featureFlags: featureFlags)
        }
    }
}
