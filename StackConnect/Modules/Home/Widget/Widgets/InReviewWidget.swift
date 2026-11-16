import Combine
import SwiftUI

@MainActor
final class InReviewWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .inReview

    let configuration: HomeWidgetConfiguration

    /// In Review rows of both stores: App Store versions expanded per platform,
    /// then Google Play releases in review, not approved or not sent (plan H3).
    @Published private(set) var entries: [DashboardEntry] = []
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
            // Accounts are loaded *before* categorizing: apps orphaned by an
            // account that went away must not be expanded, counted, or listed.
            let accounts = await HomeWidgetDataLoader.loadAccounts(storage: storage)
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let active = HomeWidgetDataLoader.filterKnownAccounts(
                allApps.filter { !$0.isArchived },
                accountsMap: accounts
            )
            let googlePlay = await HomeWidgetDataLoader.loadGooglePlaySources(
                storage: storage, accounts: accounts, requiring: .version, includesReleaseCaches: true
            )
            entries = DashboardEntryBuilder.merged(
                appStore: DashboardEntryBuilder.appStoreInReview(active, accounts: accounts),
                googlePlay: DashboardEntryBuilder.googlePlayInReview(googlePlay)
            )
        } catch {
            Log.print.error("[Widget][InReview] Failed to load apps: \(error.localizedDescription)")
            entries = []
        }
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
                count: widget.entries.count,
                tint: .orange
            )

            if widget.entries.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "checkmark.circle",
                    text: String(localized: "No apps in review")
                )
            } else {
                HomeDashboardEntryList(entries: widget.entries) { entry in
                    coordinator.open(entry.target, accountId: entry.accountId, account: entry.account)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
