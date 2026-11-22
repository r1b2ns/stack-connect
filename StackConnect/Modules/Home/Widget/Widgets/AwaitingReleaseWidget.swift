import Combine
import SwiftUI

@MainActor
final class AwaitingReleaseWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .awaitingRelease

    let configuration: HomeWidgetConfiguration

    /// Awaiting-release rows of both stores, each with its progress: App Store
    /// versions expanded per platform (an app phasing on both iOS and tvOS
    /// yields two rows), then Google Play approved releases and staged rollouts.
    @Published private(set) var entries: [DashboardEntry] = []
    @Published private(set) var isLoading: Bool = false
    /// Problems of the rows' accounts, keyed by account id: an affected
    /// account's rows show its status chip (the list mixes accounts).
    @Published private(set) var accountStatuses: [String: AccountStatus] = [:]

    /// A Play rollout percentage is shown: say how fresh it is (plan H3).
    var showsRolloutFootnote: Bool {
        entries.contains {
            if case .rollout = $0.progress { return true }
            return false
        }
    }

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
            let phased = await HomeWidgetDataLoader.loadPhasedReleases(for: active, storage: storage)
            let googlePlay = await HomeWidgetDataLoader.loadGooglePlaySources(
                storage: storage, accounts: accounts, requiring: .version, includesReleaseCaches: true, featureFlags: featureFlags
            )
            entries = DashboardEntryBuilder.merged(
                appStore: DashboardEntryBuilder.appStoreAwaitingRelease(active, phasedByVersionId: phased, accounts: accounts),
                googlePlay: DashboardEntryBuilder.googlePlayAwaitingRelease(googlePlay)
            )
        } catch {
            Log.print.error("[Widget][AwaitingRelease] Failed to load apps: \(error.localizedDescription)")
            entries = []
        }
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
                count: widget.entries.count,
                tint: .blue
            )

            if widget.entries.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "checkmark.circle",
                    text: String(localized: "Nothing awaiting release")
                )
            } else {
                HomeDashboardEntryList(entries: widget.entries, accountStatuses: widget.accountStatuses) { entry in
                    coordinator.open(entry.target, accountId: entry.accountId, account: entry.account)
                }
                if widget.showsRolloutFootnote {
                    HomeWidgetFootnote(text: String(
                        localized: "The Android rollout percentage is the last value read in the app; background sync can't read it without opening a Play edit.",
                        comment: "Home Awaiting Release footnote under Google Play staged rollout rows."
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
