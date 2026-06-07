import Combine
import StackHomeCore

/// iOS observable adapter over the Foundation-pure `StackHomeCore.InReviewWidget`.
///
/// T-A6 moved the pure `load()` logic + typed result (`InReviewWidgetData`) into
/// core. This iOS-side wrapper delegates loading to the core widget and
/// republishes its result (`@Published data`/`isLoading`) so the SwiftUI widget
/// view bound via `@ObservedObject` updates. The view itself is built by
/// `HomeWidgetViewFactory` (T-A7); the old `HomeWidgetViewProviding.makeView()`
/// bridge has been removed.
@MainActor
final class InReviewWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .inReview

    var configuration: HomeWidgetConfiguration { core.configuration }

    @Published private(set) var data = InReviewWidgetData()
    @Published private(set) var isLoading: Bool = false

    private let core: StackHomeCore.InReviewWidget

    init(configuration: HomeWidgetConfiguration, storage: PersistentStorable) {
        self.core = StackHomeCore.InReviewWidget(configuration: configuration, storage: storage)
    }

    func load() async {
        isLoading = true
        await core.load()
        data = core.data
        isLoading = false
    }
}
