import Combine
import StackHomeCore

/// iOS observable adapter over the Foundation-pure
/// `StackHomeCore.AwaitingReleaseWidget`.
///
/// T-A6 moved the pure `load()` logic + typed result (`AwaitingReleaseWidgetData`)
/// into core. This wrapper republishes the result (`@Published data`/`isLoading`)
/// for the SwiftUI widget view bound via `@ObservedObject`. The view itself is
/// built by `HomeWidgetViewFactory` (T-A7); the old
/// `HomeWidgetViewProviding.makeView()` bridge has been removed.
@MainActor
final class AwaitingReleaseWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .awaitingRelease

    var configuration: HomeWidgetConfiguration { core.configuration }

    @Published private(set) var data = AwaitingReleaseWidgetData()
    @Published private(set) var isLoading: Bool = false

    private let core: StackHomeCore.AwaitingReleaseWidget

    init(configuration: HomeWidgetConfiguration, storage: PersistentStorable) {
        self.core = StackHomeCore.AwaitingReleaseWidget(configuration: configuration, storage: storage)
    }

    func load() async {
        isLoading = true
        await core.load()
        data = core.data
        isLoading = false
    }
}
