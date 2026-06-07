import Combine
import StackHomeCore
import SwiftUI

/// iOS observable adapter over the Foundation-pure
/// `StackHomeCore.RecentReviewsWidget`.
///
/// T-A6 moved the pure `load()` logic + typed result (`RecentReviewsWidgetData`,
/// capped at 5 reviews) into core. This wrapper republishes the result for
/// SwiftUI and keeps the interim `HomeWidgetViewProviding.makeView()` bridge
/// alive until T-A7.
@MainActor
final class RecentReviewsWidget: HomeWidget, HomeWidgetViewProviding, ObservableObject {

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

    func makeView() -> AnyView {
        AnyView(RecentReviewsWidgetView(widget: self))
    }
}

// MARK: - View

private struct RecentReviewsWidgetView: View {

    @ObservedObject var widget: RecentReviewsWidget
    @EnvironmentObject private var coordinator: HomeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeWidgetSectionHeader(
                icon: "star.bubble.fill",
                title: String(localized: "Recent Reviews"),
                count: widget.data.reviews.count,
                tint: .yellow
            )

            if widget.data.reviews.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "clock.arrow.circlepath",
                    text: String(localized: "Reviews will appear after the next sync")
                )
            } else {
                ForEach(Array(widget.data.reviews.enumerated()), id: \.element.id) { index, item in
                    Button {
                        coordinator.navigateToReviewDetail(
                            review: item.review,
                            appName: item.app.name,
                            account: HomeWidgetDataLoader.account(for: item.app, in: widget.data.accountsMap)
                        )
                    } label: {
                        HomeReviewRowView(item: item)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)

                    if index < widget.data.reviews.count - 1 {
                        Divider()
                    }
                }

                Button {
                    coordinator.navigateToAllReviews()
                } label: {
                    HStack(spacing: 4) {
                        Text(String(localized: "See more"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
