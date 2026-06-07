import Combine
import StackHomeCore
import SwiftUI

/// iOS observable adapter over the Foundation-pure `StackHomeCore.InReviewWidget`.
///
/// T-A6 moved the pure `load()` logic + typed result (`InReviewWidgetData`) into
/// core. This iOS-side wrapper delegates loading to the core widget and
/// republishes its result so the existing SwiftUI views update, and it keeps
/// the interim `HomeWidgetViewProviding.makeView()` bridge alive until the T-A7
/// `HomeWidgetViewFactory` lands.
@MainActor
final class InReviewWidget: HomeWidget, HomeWidgetViewProviding, ObservableObject {

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

    func makeView() -> AnyView {
        AnyView(InReviewWidgetView(widget: self))
    }
}

// MARK: - View

private struct InReviewWidgetView: View {

    @ObservedObject var widget: InReviewWidget
    @EnvironmentObject private var coordinator: HomeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeWidgetSectionHeader(
                icon: "magnifyingglass.circle.fill",
                title: String(localized: "In Review"),
                count: widget.data.apps.count,
                tint: .orange
            )

            if widget.data.apps.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "checkmark.circle",
                    text: String(localized: "No apps in review")
                )
            } else {
                let groups = HomeWidgetPlatformGrouping.groupByPlatform(widget.data.apps)
                let showsHeaders = groups.count > 1
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if showsHeaders, let platform = group.platform {
                        HStack(spacing: 6) {
                            Image(systemName: platform.icon)
                            Text(platform.displayName)
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }

                    ForEach(group.apps) { app in
                        Button {
                            coordinator.navigateToAppDetail(
                                app,
                                account: HomeWidgetDataLoader.account(for: app, in: widget.data.accountsMap)
                            )
                        } label: {
                            HomeAppRowView(app: app, showsPlatform: true)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
