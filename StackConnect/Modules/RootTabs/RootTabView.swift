import SwiftUI

// MARK: - Factory

@MainActor
struct RootTabViewFactory {
    /// The compact-width root (iPhone, Slide Over, narrow iPad / Mac windows).
    /// The objects are owned by `AppRootViewFactory`, so the selected tab and
    /// both stacks survive size-class changes.
    static func build(coordinator: RootTabCoordinator, homeViewModel: HomeViewModel) -> some View {
        RootTabView(coordinator: coordinator, homeViewModel: homeViewModel)
    }
}

// MARK: - View

/// Two tabs: Apps (the Home stack) and Settings. Each tab has its own
/// `NavigationStack` driven by its own `HomeCoordinator`.
struct RootTabView<HomeVM: HomeViewModelProtocol>: View {

    @ObservedObject var coordinator: RootTabCoordinator
    @ObservedObject var homeViewModel: HomeVM

    var body: some View {
        TabView(selection: buildSelection()) {
            HomeViewFactory.build(viewModel: homeViewModel, coordinator: coordinator.accountsCoordinator)
                .tabItem { buildLabel(for: .accounts) }
                .tag(RootTab.accounts)

            SettingsViewFactory.buildTabRoot(coordinator: coordinator.settingsCoordinator)
                .tabItem { buildLabel(for: .settings) }
                .tag(RootTab.settings)
        }
    }

    private func buildSelection() -> Binding<RootTab> {
        Binding(
            get: { coordinator.selection },
            set: { coordinator.select($0, origin: .tabBar) }
        )
    }

    private func buildLabel(for tab: RootTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}
