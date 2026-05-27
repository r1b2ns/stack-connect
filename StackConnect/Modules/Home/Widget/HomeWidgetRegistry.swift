import Foundation

@MainActor
enum HomeWidgetRegistry {

    static let defaultConfigurations: [HomeWidgetConfiguration] = [
        HomeWidgetConfiguration(kind: .appStoreReviewCount, size: .expanded)
    ]

    static func make(
        for configuration: HomeWidgetConfiguration,
        storage: PersistentStorable
    ) -> any HomeWidget {
        switch configuration.kind {
        case .appStoreReviewCount:
            return AppStoreReviewCountWidget(configuration: configuration, storage: storage)
        }
    }
}
