import Combine
import SwiftUI

@MainActor
final class RecentReviewsWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .recentReviews

    let configuration: HomeWidgetConfiguration

    @Published private(set) var reviews: [HomeRecentReview] = []
    @Published private(set) var accountsMap: [String: AccountModel] = [:]
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
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            // Exclude archived apps so their reviews never appear in the widget.
            let active = allApps.filter { !$0.isArchived }
            let appById = Dictionary(
                active.map { ($0.id, $0) },
                uniquingKeysWith: { _, new in new }
            )
            let allReviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)
            reviews = allReviews
                .compactMap { review -> HomeRecentReview? in
                    guard let appId = review.appId, let app = appById[appId] else { return nil }
                    return HomeRecentReview(review: review, app: app)
                }
                .sorted { (a, b) in
                    (a.review.createdDate ?? .distantPast) > (b.review.createdDate ?? .distantPast)
                }
                .prefix(5)
                .map { $0 }
            accountsMap = await HomeWidgetDataLoader.loadAccounts(storage: storage)
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
                    Button {
                        coordinator.navigateToReviewDetail(
                            review: item.review,
                            appName: item.app.name,
                            account: HomeWidgetDataLoader.account(for: item.app, in: widget.accountsMap)
                        )
                    } label: {
                        HomeReviewRowView(item: item)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)

                    if index < widget.reviews.count - 1 {
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
