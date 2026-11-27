import SwiftUI
import StackProtocols

// MARK: - Sidebar Items

/// Release queues pinned to the sidebar, backed by the Home widgets of the same
/// name (same data, same rows).
enum RootReleaseQueue: String, CaseIterable, Hashable, Identifiable {
    case inReview
    case awaitingRelease

    var id: String { rawValue }

    var widgetKind: HomeWidgetKind {
        switch self {
        case .inReview:        return .inReview
        case .awaitingRelease: return .awaitingRelease
        }
    }

    var title: String { widgetKind.displayName }

    /// The `screen_name` of the queue's middle column.
    var analyticsScreen: AnalyticsScreen {
        switch self {
        case .inReview:        return .releaseQueueInReview
        case .awaitingRelease: return .releaseQueueAwaitingRelease
        }
    }

    var systemImage: String {
        switch self {
        case .inReview:        return "magnifyingglass.circle"
        case .awaitingRelease: return "paperplane.circle"
        }
    }
}

/// Team tools of an account, shown as sub-items of the selected account.
enum RootAccountSection: String, CaseIterable, Hashable, Identifiable {
    case apps
    case users
    case devices
    case certificates
    case identifiers
    case profiles
    case manage

    var id: String { rawValue }

    func title(for provider: ProviderType) -> String {
        switch self {
        case .apps:
            return provider == .firebase
                ? String(localized: "Projects", comment: "Split view sidebar: the Firebase projects of an account.")
                : String(localized: "Apps")
        case .users:        return String(localized: "Users and Access")
        case .devices:      return String(localized: "Devices")
        case .certificates: return String(localized: "Certificates")
        case .identifiers:  return String(localized: "Identifiers")
        case .profiles:     return String(localized: "Profiles")
        case .manage:       return String(localized: "Manage Account")
        }
    }

    var systemImage: String {
        switch self {
        case .apps:         return "square.stack.3d.up"
        case .users:        return "person.2"
        case .devices:      return "iphone.gen3"
        case .certificates: return "lock.shield"
        case .identifiers:  return "ipod.and.applewatch"
        case .profiles:     return "doc.badge.gearshape"
        case .manage:       return "gearshape"
        }
    }

    /// The sections an account offers, in sidebar order. Mirrors what the
    /// iPhone exposes: Users only with the `users` permission, the four
    /// provisioning tools only for App Store Connect accounts that can view
    /// them (same rule as Manage Account).
    static func sections(for account: AccountModel) -> [RootAccountSection] {
        var sections: [RootAccountSection] = [.apps]
        if account.providerType == .apple {
            if account.canView(.users) {
                sections.append(.users)
            }
            if account.ruleResources.contains(.provisioning), account.canView(.provisioning) {
                sections.append(contentsOf: [.devices, .certificates, .identifiers, .profiles])
            }
        }
        sections.append(.manage)
        return sections
    }
}

/// A sidebar selection. Accounts are referenced by id so the selection
/// survives a reload of the account (rename, new expiration, rules).
enum RootSidebarItem: Hashable {
    case dashboard
    case releaseQueue(RootReleaseQueue)
    case recentReviews
    case account(id: String, section: RootAccountSection)
    case addAccount(ProviderType)
    case settings

    var accountId: String? {
        if case let .account(id, _) = self { return id }
        return nil
    }

    /// `true` when the item lists things in the middle column (three columns);
    /// `false` when it opens straight in the wide detail column (two columns):
    /// the Dashboard, and Users and Access (a table with an inspector).
    var usesContentColumn: Bool {
        switch self {
        case .dashboard, .account(_, .users): return false
        default: return true
        }
    }
}

// MARK: - Coordinator

/// Navigation state of the regular-width root (`RootSplitView`): the sidebar
/// selection, the detail column's root and stack, and the column visibility.
/// Keeping it here (not in view `@State`) lets deep links, and later menu-bar
/// commands and keyboard shortcuts, drive the split view.
///
/// Every existing screen navigates through the `HomeCoordinator` it reads from
/// the environment, so the split view hands two of them out:
/// - `contentCoordinator` (middle column): its routes don't push, they become
///   the detail column's root (`showInDetail`).
/// - `detailCoordinator` (detail column): a plain stack (its `path`), so
///   pushes from inside the detail keep working as on iPhone.
@MainActor
final class RootSplitCoordinator: ObservableObject {

    @Published private(set) var selection: RootSidebarItem = .dashboard
    /// Root screen of the detail column for list items; `nil` shows the
    /// "nothing selected" placeholder (or the dashboard when it is selected).
    @Published private(set) var detailRoute: HomeRoute?
    @Published var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// Bumped whenever accounts may have changed behind the sidebar's back (an
    /// account deleted from a column), so it reloads.
    @Published private(set) var accountsRevision = 0
    /// Bumped by the Find command (⌘F); see `stackSearchShortcutFocus()`.
    @Published private(set) var searchRequest = 0

    let contentCoordinator = HomeCoordinator()
    let detailCoordinator = HomeCoordinator()

    private let analytics: AnalyticsTracking

    init(analytics: AnalyticsTracking = AnalyticsService.shared) {
        self.analytics = analytics
        contentCoordinator.routeHandler = { [weak self] route in
            self?.showInDetail(route)
        }
        // Deleting an account (Manage Account) or every account (Settings)
        // asks to pop to the root: go back to the dashboard.
        contentCoordinator.popToRootHandler = { [weak self] in
            self?.returnToDashboard()
        }
        detailCoordinator.popToRootHandler = { [weak self] in
            self?.returnToDashboard()
        }
    }

    /// Sidebar selection. Changing it clears the detail column.
    ///
    /// The single choke point of user navigation between sidebar items (the
    /// sidebar, the menu-bar commands and the dashboard KPI tiles all come
    /// through here), so it sends one `navigate` action per actual change,
    /// with `origin`. Reselecting the current item sends nothing. Programmatic
    /// moves (deep links, pop to root) don't come through here and are not
    /// tracked as navigation.
    func select(_ item: RootSidebarItem, origin: AnalyticsNavigationOrigin) {
        guard item != selection else { return }
        selection = item
        resetDetail()
        restoreColumnsIfNeeded()
        analytics.track(.navigate(to: item, from: origin))
    }

    /// Opens `route` as the detail column's root (a row picked in the middle
    /// column), dropping whatever was pushed on top of the previous one.
    func showInDetail(_ route: HomeRoute) {
        detailRoute = route
        detailCoordinator.path = NavigationPath()
        if Self.usesFullWidth(route) {
            // A screen with its own list + detail (the network audit) takes the
            // whole width: the sidebar and the middle column collapse; the
            // system's sidebar button brings them back.
            columnVisibility = .detailOnly
            collapsedForFullWidth = true
        } else {
            restoreColumnsIfNeeded()
        }
    }

    /// Detail roots laid out as two columns of their own.
    static func usesFullWidth(_ route: HomeRoute) -> Bool {
        if case .networkAudit = route { return true }
        return false
    }

    /// `true` while the columns are collapsed by `showInDetail`.
    private(set) var collapsedForFullWidth = false

    private func restoreColumnsIfNeeded() {
        guard collapsedForFullWidth else { return }
        collapsedForFullWidth = false
        columnVisibility = .automatic
    }

    /// The Find command (⌘F): focus the search field of the screen on display.
    /// Tracked as a `find` action from the menu command (its only caller).
    func requestSearch() {
        searchRequest += 1
        analytics.track(.action(
            .find,
            on: nil,
            parameters: [AnalyticsParameterKey.source: .string(AnalyticsNavigationOrigin.menuCommand.rawValue)]
        ))
    }

    func returnToDashboard() {
        accountsRevision += 1
        selection = .dashboard
        resetDetail()
        restoreColumnsIfNeeded()
    }

    private func resetDetail() {
        detailRoute = nil
        detailCoordinator.path = NavigationPath()
    }
}

// MARK: - Deep Links

extension RootSplitCoordinator: HomeRootNavigating {
    // `restoreColumnsIfNeeded()`: a link opened while the audit holds the
    // whole width brings the sidebar back.
    func showHome() {
        selection = .dashboard
        resetDetail()
        restoreColumnsIfNeeded()
    }

    func showAllReviews() {
        selection = .recentReviews
        resetDetail()
        restoreColumnsIfNeeded()
    }

    /// Selects Settings and opens the audit as the detail root, as the
    /// Settings row does (full width; the sidebar button brings Settings back).
    func showNetworkAudit() {
        selection = .settings
        showInDetail(.networkAudit)
    }

    /// Opens on top of the dashboard, so Back returns to it (as on iPhone,
    /// where links open on top of the Home).
    func show(_ route: HomeRoute) {
        showHome()
        detailCoordinator.push(route)
    }

    /// Selects the account's section in the sidebar (its list fills the
    /// middle column); the first route becomes the detail root, as a row
    /// picked in that list, and the others are pushed on the detail stack.
    func showAccount(_ account: AccountModel, section: RootAccountSection, routes: [HomeRoute]) {
        selection = .account(id: account.id, section: section)
        resetDetail()
        restoreColumnsIfNeeded()
        guard let first = routes.first else { return }
        showInDetail(first)
        routes.dropFirst().forEach(detailCoordinator.push)
    }
}
