import Combine
import StackHomeCore
import SwiftUI

/// iOS observable adapter over the Foundation-pure
/// `StackHomeCore.AwaitingReleaseWidget`.
///
/// T-A6 moved the pure `load()` logic + typed result (`AwaitingReleaseWidgetData`)
/// into core. This wrapper republishes the result for SwiftUI and keeps the
/// interim `HomeWidgetViewProviding.makeView()` bridge alive until T-A7.
@MainActor
final class AwaitingReleaseWidget: HomeWidget, HomeWidgetViewProviding, ObservableObject {

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

    func makeView() -> AnyView {
        AnyView(AwaitingReleaseWidgetView(widget: self))
    }
}

// MARK: - View

private struct AwaitingReleaseWidgetView: View {

    @ObservedObject var widget: AwaitingReleaseWidget
    @EnvironmentObject private var coordinator: HomeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeWidgetSectionHeader(
                icon: "paperplane.circle.fill",
                title: String(localized: "Awaiting Release"),
                count: widget.data.apps.count,
                tint: .blue
            )

            if widget.data.apps.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "checkmark.circle",
                    text: String(localized: "Nothing awaiting release")
                )
            } else {
                ForEach(widget.data.apps) { app in
                    Button {
                        coordinator.navigateToAppDetail(
                            app,
                            account: HomeWidgetDataLoader.account(for: app, in: widget.data.accountsMap)
                        )
                    } label: {
                        buildRow(app)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildRow(_ app: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeAppRowView(app: app)
            if let phased = widget.data.phasedByAppId[app.id],
               phased.state == .active || phased.state == .paused,
               let day = phased.currentDayNumber {
                HomePhasedProgressView(day: day, total: 7, paused: phased.state == .paused)
                    .padding(.leading, 56)
            }
        }
    }
}
