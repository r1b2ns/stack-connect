import SwiftUI
import StackProtocols

// MARK: - Tabs

/// The tabs of the compact-width root (`RootTabView`).
enum RootTab: String, CaseIterable, Hashable {
    /// The Home stack: banners, the provider mosaic and the widgets.
    case accounts
    /// The Settings screen as a tab root.
    case settings

    var title: String {
        switch self {
        case .accounts: return String(localized: "Apps")
        case .settings: return String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .accounts: return "apps.iphone"
        case .settings: return "gearshape"
        }
    }

    /// `destination` of the `navigate` action. The Apps tab is the
    /// iPhone Home, the compact counterpart of the split view's dashboard.
    var analyticsDestination: AnalyticsSidebarDestination {
        switch self {
        case .accounts: return .dashboard
        case .settings: return .settings
        }
    }
}

// MARK: - Coordinator

/// Navigation state of the compact-width root: the selected tab and one
/// `HomeCoordinator` per tab, each driving its own `NavigationStack`. Every
/// screen keeps navigating through the `HomeCoordinator` it reads from the
/// environment, so screens reached from Settings (account management, tip
/// jar, license…) push on the Settings stack without knowing about tabs.
///
/// Owned by `AppRootViewFactory`, so the tab and both stacks survive
/// size-class changes.
@MainActor
final class RootTabCoordinator: ObservableObject {

    @Published private(set) var selection: RootTab = .accounts

    let accountsCoordinator: HomeCoordinator
    let settingsCoordinator: HomeCoordinator

    private let analytics: AnalyticsTracking

    init(
        accountsCoordinator: HomeCoordinator = HomeCoordinator(),
        settingsCoordinator: HomeCoordinator = HomeCoordinator(),
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.accountsCoordinator = accountsCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.analytics = analytics
        // Deleting an account (Manage Account) or every account (Settings)
        // asks to pop to the root: unwind both stacks, so neither tab keeps
        // showing screens of an account that is gone.
        accountsCoordinator.popToRootHandler = { [weak self] in
            self?.resetStacks()
        }
        settingsCoordinator.popToRootHandler = { [weak self] in
            self?.resetStacks()
        }
    }

    /// User tab selection (the tab bar). Sends one `navigate` action per
    /// actual change; reselecting the current tab sends nothing. Programmatic
    /// moves (deep links) don't come through here and are not tracked.
    func select(_ tab: RootTab, origin: AnalyticsNavigationOrigin = .tabBar) {
        guard tab != selection else { return }
        selection = tab
        analytics.track(.navigate(to: tab.analyticsDestination, from: origin))
    }

    private func resetStacks() {
        accountsCoordinator.path = NavigationPath()
        settingsCoordinator.path = NavigationPath()
    }
}

// MARK: - Deep Links

/// Every deep link opens in the Apps tab, on top of the Home, as before
/// the tab bar existed — except the network audit, which lives in Settings
/// and opens on the Settings stack (Back returns to Settings).
extension RootTabCoordinator: HomeRootNavigating {
    func showHome() {
        selection = .accounts
        accountsCoordinator.showHome()
    }

    func showAllReviews() {
        selection = .accounts
        accountsCoordinator.showAllReviews()
    }

    func showNetworkAudit() {
        selection = .settings
        settingsCoordinator.showNetworkAudit()
    }

    func show(_ route: HomeRoute) {
        selection = .accounts
        accountsCoordinator.show(route)
    }

    func showAccount(_ account: AccountModel, section: RootAccountSection, routes: [HomeRoute]) {
        selection = .accounts
        accountsCoordinator.showAccount(account, section: section, routes: routes)
    }
}
