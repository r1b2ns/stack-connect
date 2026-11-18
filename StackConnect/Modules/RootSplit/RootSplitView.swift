import SwiftUI

// MARK: - Factory

@MainActor
struct RootSplitViewFactory {
    /// The regular-width root (iPad full screen / wide multitasking, Mac
    /// windows). The objects are owned by `AppRootViewFactory`, so selection
    /// and stacks survive size-class changes.
    static func build(
        coordinator: RootSplitCoordinator,
        homeViewModel: HomeViewModel,
        sidebarViewModel: RootSidebarViewModel
    ) -> some View {
        RootSplitView(
            coordinator: coordinator,
            homeViewModel: homeViewModel,
            sidebarViewModel: sidebarViewModel
        )
    }
}

// MARK: - View

/// Sidebar → list → detail. Items that list things (accounts, queues, reviews,
/// settings) use three columns; the Dashboard uses two (sidebar + a wide
/// detail). In a narrow regular window or in portrait the sidebar collapses on
/// its own; compact width never gets here (`AppRootView`).
struct RootSplitView<HomeVM: HomeViewModelProtocol, SidebarVM: RootSidebarViewModelProtocol>: View {

    @ObservedObject var coordinator: RootSplitCoordinator
    @ObservedObject var homeViewModel: HomeVM
    @ObservedObject var sidebarViewModel: SidebarVM

    var body: some View {
        Group {
            if coordinator.selection.usesContentColumn {
                NavigationSplitView(columnVisibility: $coordinator.columnVisibility) {
                    buildSidebar()
                } content: {
                    buildContentColumn()
                } detail: {
                    buildDetailColumn()
                }
            } else {
                NavigationSplitView(columnVisibility: $coordinator.columnVisibility) {
                    buildSidebar()
                } detail: {
                    buildDetailColumn()
                }
            }
        }
        // Sidebar beside the columns (not over them) whenever it is shown.
        .navigationSplitViewStyle(.balanced)
        .task { await sidebarViewModel.load() }
        // Cheap local reload: picks up accounts added or removed from a column.
        .onChange(of: coordinator.selection) {
            Task { await sidebarViewModel.load() }
        }
        .onChange(of: coordinator.accountsRevision) {
            Task { await sidebarViewModel.load() }
        }
        .homeDeepLinks(coordinator)
    }

    // MARK: - Sidebar

    private func buildSidebar() -> some View {
        RootSidebarView(
            viewModel: sidebarViewModel,
            selection: Binding(
                get: { coordinator.selection },
                set: { item in
                    if let item { coordinator.select(item) }
                }
            )
        )
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }

    // MARK: - Content Column

    private func buildContentColumn() -> some View {
        buildContent(for: coordinator.selection)
            // A new selection is a new screen: fresh view models.
            .id(coordinator.selection)
            .environmentObject(coordinator.contentCoordinator)
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
    }

    @ViewBuilder
    private func buildContent(for item: RootSidebarItem) -> some View {
        switch item {
        case .dashboard:
            // Two-column layout: no content column.
            EmptyView()
        case .releaseQueue(let queue):
            RootReleaseQueueView(queue: queue, widget: sidebarViewModel.widget(for: queue)) {
                await sidebarViewModel.load()
            }
        case .recentReviews:
            AllReviewsViewFactory.build(showsFilter: true)
        case .account(let id, let section):
            if let account = sidebarViewModel.account(id: id) {
                RootAccountContentView(account: account, section: section)
            } else if sidebarViewModel.uiState.hasLoaded {
                ContentUnavailableView(
                    String(localized: "Account Not Found", comment: "Split view: the selected account no longer exists."),
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            } else {
                ProgressView()
            }
        case .addAccount(let provider):
            AccountsListViewFactory.build(providerType: provider)
        case .settings:
            SettingsViewFactory.build()
        }
    }

    // MARK: - Detail Column

    private func buildDetailColumn() -> some View {
        RootDetailStack(coordinator: coordinator.detailCoordinator) {
            buildDetailRoot()
        }
    }

    @ViewBuilder
    private func buildDetailRoot() -> some View {
        if coordinator.selection == .dashboard {
            RootDashboardView(viewModel: homeViewModel, sidebarViewModel: sidebarViewModel) { queue in
                coordinator.select(.releaseQueue(queue))
            }
        } else if let route = coordinator.detailRoute {
            HomeRouteView(route: route)
                .id(route)
        } else {
            ContentUnavailableView(
                String(localized: "Nothing Selected", comment: "Split view detail column placeholder title."),
                systemImage: "sidebar.squares.left",
                description: Text(String(localized: "Choose an item from the list.", comment: "Split view detail column placeholder message."))
            )
        }
    }
}

// MARK: - Detail Stack

/// The detail column's `NavigationStack`, bound to its own `HomeCoordinator`
/// so screens pushed from inside the detail keep working as on iPhone.
private struct RootDetailStack<Root: View>: View {

    @ObservedObject var coordinator: HomeCoordinator
    @ViewBuilder let root: () -> Root

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            root()
                .environmentObject(coordinator)
                .homeNavigationDestinations(coordinator: coordinator)
        }
        .environmentObject(coordinator)
    }
}
