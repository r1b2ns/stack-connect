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
    /// Problems of the rows' accounts, keyed by account id: an affected
    /// account's rows show its status chip (the list mixes accounts).
    @Published private(set) var accountStatuses: [String: AccountStatus] = [:]

    private let storage: PersistentStorable
    /// Decides whether Google Play rows are shown (`googlePlayAccounts`).
    private let featureFlags: FeatureFlags
    private let statusResolver: AccountStatusResolving

    init(
        configuration: HomeWidgetConfiguration,
        storage: PersistentStorable,
        featureFlags: FeatureFlags = .shared,
        statusResolver: AccountStatusResolving? = nil
    ) {
        self.configuration = configuration
        self.storage = storage
        self.featureFlags = featureFlags
        self.statusResolver = statusResolver ?? AccountStatusResolver(keychain: KeychainStorable.shared)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Accounts are loaded *before* categorizing: apps orphaned by an
            // account that went away must not be expanded, counted, or listed.
            let accounts = await HomeWidgetDataLoader.loadAccounts(storage: storage, featureFlags: featureFlags)
            accountStatuses = statusResolver.statuses(for: Array(accounts.values))
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let active = HomeWidgetDataLoader.filterKnownAccounts(
                allApps.filter { !$0.isArchived },
                accountsMap: accounts
            )
            let googlePlay = await HomeWidgetDataLoader.loadGooglePlaySources(
                storage: storage, accounts: accounts, requiring: .version, includesReleaseCaches: true, featureFlags: featureFlags
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
                HomeDashboardEntryList(entries: widget.entries, accountStatuses: widget.accountStatuses) { entry in
                    coordinator.open(entry.target, accountId: entry.accountId, account: entry.account)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
