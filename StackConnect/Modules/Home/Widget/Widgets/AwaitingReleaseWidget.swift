import Combine
import SwiftUI

@MainActor
final class AwaitingReleaseWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .awaitingRelease

    let configuration: HomeWidgetConfiguration

    /// Awaiting-release rows, expanded per platform version (an app phasing on
    /// both iOS and tvOS yields two rows), each with its progress.
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
            let phased = await HomeWidgetDataLoader.loadPhasedReleases(for: active, storage: storage)
            entries = DashboardEntryBuilder.appStoreAwaitingRelease(active, phasedByVersionId: phased, accounts: accounts)
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
                HomeDashboardEntryList(entries: widget.entries) { entry in
                    coordinator.open(entry.target, accountId: entry.accountId, account: entry.account)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
