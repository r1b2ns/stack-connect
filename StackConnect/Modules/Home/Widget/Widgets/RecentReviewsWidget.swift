import Combine
import StackHomeCore

/// iOS observable adapter over the Foundation-pure
/// `StackHomeCore.RecentReviewsWidget`.
///
/// T-A6 moved the pure `load()` logic + typed result (`RecentReviewsWidgetData`,
/// capped at 5 reviews) into core. This wrapper republishes the result
/// (`@Published data`/`isLoading`) for the SwiftUI widget view bound via
/// `@ObservedObject`. The view itself is built by `HomeWidgetViewFactory`
/// (T-A7); the old `HomeWidgetViewProviding.makeView()` bridge has been removed.
@MainActor
final class RecentReviewsWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .recentReviews

    var configuration: HomeWidgetConfiguration { core.configuration }

    @Published private(set) var data = RecentReviewsWidgetData()
    @Published private(set) var isLoading: Bool = false

    private let core: StackHomeCore.RecentReviewsWidget

    init(configuration: HomeWidgetConfiguration, storage: PersistentStorable) {
        self.core = StackHomeCore.RecentReviewsWidget(configuration: configuration, storage: storage)
    }

    func load() async {
        isLoading = true
        await core.load()
        data = core.data
        isLoading = false
    }
}
