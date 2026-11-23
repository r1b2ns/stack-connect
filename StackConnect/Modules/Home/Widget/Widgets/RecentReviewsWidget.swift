import Combine
import SwiftUI

@MainActor
final class RecentReviewsWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .recentReviews

    let configuration: HomeWidgetConfiguration

    @Published private(set) var reviews: [DashboardReview] = []
    @Published private(set) var isLoading: Bool = false

    /// Google Play reviews are listed: say which ones Google shares.
    var showsGooglePlayFootnote: Bool {
        reviews.contains { $0.provider == .googlePlay }
    }

    private let storage: PersistentStorable
    /// Decides whether Google Play rows are shown (`googlePlayAccounts`).
    private let featureFlags: FeatureFlags

    init(configuration: HomeWidgetConfiguration, storage: PersistentStorable, featureFlags: FeatureFlags = .shared) {
        self.configuration = configuration
        self.storage = storage
        self.featureFlags = featureFlags
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Accounts are loaded first so reviews belonging to apps orphaned by
            // an account that went away never resolve into a row.
            let accounts = await HomeWidgetDataLoader.loadAccounts(storage: storage, featureFlags: featureFlags)
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            // Exclude archived apps so their reviews never appear in the widget.
            let active = HomeWidgetDataLoader.filterKnownAccounts(
                allApps.filter { !$0.isArchived },
                accountsMap: accounts
            )
            let googlePlay = await HomeWidgetDataLoader.loadGooglePlaySources(
                storage: storage, accounts: accounts, requiring: .review, includesReleaseCaches: false, featureFlags: featureFlags
            )
            let allReviews: [CustomerReviewModel] = try await storage.fetchAll(CustomerReviewModel.self)
            reviews = DashboardEntryBuilder.reviews(
                allReviews,
                appStoreApps: active,
                googlePlaySources: googlePlay,
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
                    StackTrackedButton(.widgetReview, onCurrentScreenOr: .home) {
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

                StackTrackedButton(.seeMore, onCurrentScreenOr: .home) {
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

                if widget.showsGooglePlayFootnote {
                    HomeWidgetFootnote(text: String(
                        localized: "Google Play only shares reviews with a comment from the last 7 days.",
                        comment: "Home Recent Reviews footnote when Google Play reviews are listed."
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
