import Combine
import StackHomeCore
import SwiftUI

@MainActor
final class AwaitingReleaseWidget: HomeWidget, HomeWidgetViewProviding, ObservableObject {

    static let kind: HomeWidgetKind = .awaitingRelease

    let configuration: HomeWidgetConfiguration

    @Published private(set) var apps: [AppModel] = []
    @Published private(set) var phasedByAppId: [String: PhasedReleaseModel] = [:]
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
            let active = allApps.filter { !$0.isArchived }
            let phased = await HomeWidgetDataLoader.loadPhasedReleases(for: active, storage: storage)
            let (_, awaiting) = AppStatusCategorizer.categorize(active, phasedByAppId: phased)
            apps = awaiting.sorted(by: HomeWidgetDataLoader.sortByRecency)
            phasedByAppId = phased
            accountsMap = await HomeWidgetDataLoader.loadAccounts(storage: storage)
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
                ForEach(widget.apps) { app in
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildRow(_ app: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeAppRowView(app: app)
            if let phased = widget.phasedByAppId[app.id],
               phased.state == .active || phased.state == .paused,
               let day = phased.currentDayNumber {
                HomePhasedProgressView(day: day, total: 7, paused: phased.state == .paused)
                    .padding(.leading, 56)
            }
        }
    }
}
