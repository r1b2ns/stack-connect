import Combine
import SwiftUI

@MainActor
final class RecentReviewsWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .recentReviews

    let configuration: HomeWidgetConfiguration

    @Published private(set) var reviews: [DashboardReview] = []
    @Published private(set) var isLoading: Bool = false

    private let storage: PersistentStorable

    init(configuration: HomeWidgetConfiguration, storage: PersistentStorable) {
        self.configuration = configuration
        self.storage = storage
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Accounts are loaded first so reviews belonging to apps orphaned by
            // an account that went away never resolve into a row.
            let accounts = await HomeWidgetDataLoader.loadAccounts(storage: storage)
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            // Exclude archived apps so their reviews never appear in the widget.
            let active = HomeWidgetDataLoader.filterKnownAccounts(
                allApps.filter { !$0.isArchived },
                accountsMap: accounts
            )
            let allReviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)
            reviews = DashboardEntryBuilder.reviews(
                allReviews,
                appStoreApps: active,
                googlePlaySources: [],
                accounts: accounts,
                limit: 5
            )
        } catch {
            Log.print.error("[Widget][RecentReviews] Failed to load reviews: \(error.localizedDescription)")
            reviews = []
        }
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
                count: widget.reviews.count,
                tint: .yellow
            )

            if widget.reviews.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "clock.arrow.circlepath",
                    text: String(localized: "Reviews will appear after the next sync")
                )
            } else {
                ForEach(Array(widget.reviews.enumerated()), id: \.element.id) { index, item in
                    StackTrackedButton(.widgetReview, on: .home) {
                        coordinator.open(item)
                    } label: {
                        HomeReviewRowView(item: item)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)

                    if index < widget.reviews.count - 1 {
                        Divider()
                    }
                }

                StackTrackedButton(.seeMore, on: .home) {
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
