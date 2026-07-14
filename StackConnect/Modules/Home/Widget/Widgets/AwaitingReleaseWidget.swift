import Combine
import SwiftUI

@MainActor
final class AwaitingReleaseWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .awaitingRelease

    let configuration: HomeWidgetConfiguration

    /// Awaiting-release entries, expanded per platform (an app phasing on both
    /// iOS and tvOS yields two entries).
    @Published private(set) var apps: [AppModel] = []
    /// Phased releases keyed by version id (matches the `"phased.{versionId}"`
    /// storage scheme). Look up per entry via `HomeWidgetDataLoader.phasedRelease`.
    @Published private(set) var phasedByVersionId: [String: PhasedReleaseModel] = [:]
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
            // Accounts are loaded *before* categorizing: apps orphaned by an
            // account that went away must not be expanded, counted, or listed.
            let accounts = await HomeWidgetDataLoader.loadAccounts(storage: storage)
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let active = HomeWidgetDataLoader.filterKnownAccounts(
                allApps.filter { !$0.isArchived },
                accountsMap: accounts
            )
            let phased = await HomeWidgetDataLoader.loadPhasedReleases(for: active, storage: storage)
            let awaiting = AppStatusCategorizer.awaitingReleaseEntries(active, phasedByVersionId: phased)
            apps = awaiting.sorted(by: HomeWidgetDataLoader.sortByRecency)
            phasedByVersionId = phased
            accountsMap = accounts
        } catch {
            Log.print.error("[Widget][AwaitingRelease] Failed to load apps: \(error.localizedDescription)")
            apps = []
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
                count: widget.apps.count,
                tint: .blue
            )

            if widget.apps.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "checkmark.circle",
                    text: String(localized: "Nothing awaiting release")
                )
            } else {
                let groups = HomeWidgetDataLoader.groupByPlatform(widget.apps)
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

                    // Identified by platform + version, not `AppModel.id`: rows are
                    // per-version copies of one app, so the bare id repeats.
                    ForEach(group.apps, id: \.statusEntryID) { app in
                        Button {
                            coordinator.navigateToAppDetail(
                                app,
                                account: HomeWidgetDataLoader.account(for: app, in: widget.accountsMap)
                            )
                        } label: {
                            buildRow(app)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildRow(_ app: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeAppRowView(app: app, showsPlatform: true)
            if let phased = HomeWidgetDataLoader.phasedRelease(for: app, in: widget.phasedByVersionId),
               phased.state == .active || phased.state == .paused,
               let day = phased.currentDayNumber {
                HomePhasedProgressView(day: day, total: 7, paused: phased.state == .paused)
                    .padding(.leading, 56)
            }
        }
    }
}
