import SwiftUI

// MARK: - Factory

@MainActor
struct AppRootViewFactory {
    static func build() -> some View {
        AppRootEntry()
    }
}

// MARK: - Entry

/// Owns the navigation state of both root layouts for the whole app life, so a
/// size-class change (rotation, multitasking, resizing a Mac window) swaps the
/// layout without losing the Home data, the compact stack or the split view
/// selection.
private struct AppRootEntry: View {
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var homeCoordinator = HomeCoordinator()
    @StateObject private var splitCoordinator = RootSplitCoordinator()
    @StateObject private var sidebarViewModel = RootSidebarViewModel()

    var body: some View {
        AppRootView(
            homeViewModel: homeViewModel,
            homeCoordinator: homeCoordinator,
            splitCoordinator: splitCoordinator,
            sidebarViewModel: sidebarViewModel,
            userProperties: AnalyticsService.shared
        )
    }
}

// MARK: - View

/// Picks the root by horizontal size class only, never by device idiom or
/// orientation: compact width (iPhone, Slide Over, a narrow window) keeps the
/// iPhone Home stack exactly as it is; regular width gets `RootSplitView`.
///
/// The layout picked is also the `ui_layout` user property, set at launch and
/// again whenever the size class changes.
struct AppRootView: View {

    let homeViewModel: HomeViewModel
    let homeCoordinator: HomeCoordinator
    let splitCoordinator: RootSplitCoordinator
    let sidebarViewModel: RootSidebarViewModel
    let userProperties: any AnalyticsUserPropertySetting

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                RootSplitViewFactory.build(
                    coordinator: splitCoordinator,
                    homeViewModel: homeViewModel,
                    sidebarViewModel: sidebarViewModel
                )
                // Lets `AppCommands` reach the selection while this layout is up.
                .focusedSceneObject(splitCoordinator)
            } else {
                HomeViewFactory.build(viewModel: homeViewModel, coordinator: homeCoordinator)
                    .homeDeepLinks(homeCoordinator)
            }
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            Self.reportLayout(for: sizeClass, to: userProperties)
        }
    }

    /// The layout `body` shows for `sizeClass`: only `.regular` gets the split view.
    static func layout(for sizeClass: UserInterfaceSizeClass?) -> AnalyticsUILayout {
        sizeClass == .regular ? .regular : .compact
    }

    /// Sets `ui_layout`. `AnalyticsService` owns the opt-out gate and drops
    /// unchanged values, so a size-class flip back and forth only sends real
    /// changes. Split out so it can be unit tested.
    static func reportLayout(for sizeClass: UserInterfaceSizeClass?, to userProperties: any AnalyticsUserPropertySetting) {
        userProperties.setUserProperties([.uiLayout: layout(for: sizeClass).rawValue])
    }
}
