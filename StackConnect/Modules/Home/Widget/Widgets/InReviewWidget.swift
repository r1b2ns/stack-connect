import Combine
import SwiftUI

@MainActor
final class InReviewWidget: HomeWidget, ObservableObject {

    static let kind: HomeWidgetKind = .inReview

    let configuration: HomeWidgetConfiguration

    @Published private(set) var apps: [AppModel] = []
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
            let phasedByAppId = await HomeWidgetDataLoader.loadPhasedReleases(for: active, storage: storage)
            let (inReview, _) = AppStatusCategorizer.categorize(active, phasedByAppId: phasedByAppId)
            apps = inReview.sorted(by: HomeWidgetDataLoader.sortByRecency)
            accountsMap = await HomeWidgetDataLoader.loadAccounts(storage: storage)
        } catch {
            Log.print.error("[Widget][InReview] Failed to load apps: \(error.localizedDescription)")
            apps = []
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
                count: widget.apps.count,
                tint: .orange
            )

            if widget.apps.isEmpty {
                HomeWidgetEmptyRow(
                    icon: "checkmark.circle",
                    text: String(localized: "No apps in review")
                )
            } else {
                ForEach(widget.apps) { app in
                    Button {
                        coordinator.navigateToAppDetail(
                            app,
                            account: HomeWidgetDataLoader.account(for: app, in: widget.accountsMap)
                        )
                    } label: {
                        HomeAppRowView(app: app)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
