import SwiftUI

/// The regular-width Home: banners, a KPI strip of the release queues and the
/// Home widgets in an adaptive grid (1 column in a narrow window, up to 4 in a
/// wide one). Driven by the same `HomeViewModel` as the compact Home.
struct RootDashboardView<ViewModel: HomeViewModelProtocol, SidebarViewModel: RootSidebarViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @ObservedObject var sidebarViewModel: SidebarViewModel
    /// Opens a release queue (the KPI tiles select its sidebar item).
    let onSelectQueue: (RootReleaseQueue) -> Void

    @EnvironmentObject private var coordinator: HomeCoordinator
    @State private var isCustomizingWidgets = false

    private let kpiColumns = [GridItem(.adaptive(minimum: 180), spacing: 16)]
    private let widgetColumns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeReconnectingTip(appleIds: viewModel.uiState.reconnectingAppleIds)
                HomeSyncBanner(syncState: viewModel.uiState.syncState)
                HomeSignInAgainBanner(viewModel: viewModel)
                HomeAgreementsBanners(viewModel: viewModel)
                HomeTipCard(viewModel: viewModel) {
                    coordinator.navigateToTipJar()
                }
                buildKPIStrip()
                buildWidgets()
            }
            .padding(20)
        }
        .navigationTitle(String(localized: "Dashboard", comment: "Split view sidebar item and title of the iPad Home."))
        .trackScreen(.home)
        .toolbar { buildToolbar() }
        .refreshable { await refresh() }
        .task {
            viewModel.triggerSync()
            await viewModel.loadDashboard()
        }
        .sheet(isPresented: $isCustomizingWidgets) {
            CustomizeWidgetsView(viewModel: viewModel)
                .stackFormSheet()
        }
        .homePresentations(viewModel: viewModel)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await refresh() }
            } label: {
                Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.uiState.syncState.isSyncing)

            StackTrackedButton(.customizeWidgets, on: .home) {
                isCustomizingWidgets = true
            } label: {
                Label(String(localized: "Customize Widgets"), systemImage: "square.grid.2x2")
            }
        }
    }

    // MARK: - KPI Strip

    private func buildKPIStrip() -> some View {
        LazyVGrid(columns: kpiColumns, alignment: .leading, spacing: 16) {
            ForEach(RootReleaseQueue.allCases) { queue in
                StackMetricTile(
                    value: sidebarViewModel.uiState.queueCounts[queue].map(String.init) ?? "–",
                    title: queue.title,
                    systemImage: queue.widgetKind.systemImage,
                    tint: queue.widgetKind.tintColor
                ) {
                    onSelectQueue(queue)
                }
            }
        }
    }

    // MARK: - Widgets

    @ViewBuilder
    private func buildWidgets() -> some View {
        if viewModel.uiState.widgets.isEmpty {
            HomeWidgetsEmptyState {
                isCustomizingWidgets = true
            }
        } else {
            LazyVGrid(columns: widgetColumns, alignment: .leading, spacing: 16) {
                ForEach(viewModel.uiState.widgets, id: \.id) { widget in
                    HomeWidgetContainerView(widget: widget)
                }
            }
        }
    }

    private func refresh() async {
        await viewModel.refresh()
        await sidebarViewModel.load()
    }
}
