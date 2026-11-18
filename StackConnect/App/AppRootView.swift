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
            sidebarViewModel: sidebarViewModel
        )
    }
}

// MARK: - View

/// Picks the root by horizontal size class only, never by device idiom or
/// orientation: compact width (iPhone, Slide Over, a narrow window) keeps the
/// iPhone Home stack exactly as it is; regular width gets `RootSplitView`.
struct AppRootView: View {

    let homeViewModel: HomeViewModel
    let homeCoordinator: HomeCoordinator
    let splitCoordinator: RootSplitCoordinator
    let sidebarViewModel: RootSidebarViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            RootSplitViewFactory.build(
                coordinator: splitCoordinator,
                homeViewModel: homeViewModel,
                sidebarViewModel: sidebarViewModel
            )
        } else {
            HomeViewFactory.build(viewModel: homeViewModel, coordinator: homeCoordinator)
                .homeDeepLinks(homeCoordinator)
        }
    }
}
