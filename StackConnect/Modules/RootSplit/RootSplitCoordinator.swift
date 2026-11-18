import SwiftUI

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
    /// `false` when it opens straight in the detail column (two columns).
    var usesContentColumn: Bool {
        self != .dashboard
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

    let contentCoordinator = HomeCoordinator()
    let detailCoordinator = HomeCoordinator()

    init() {
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
    func select(_ item: RootSidebarItem) {
        guard item != selection else { return }
        selection = item
        resetDetail()
    }

    /// Opens `route` as the detail column's root (a row picked in the middle
    /// column), dropping whatever was pushed on top of the previous one.
    func showInDetail(_ route: HomeRoute) {
        detailRoute = route
        detailCoordinator.path = NavigationPath()
    }

    func returnToDashboard() {
        accountsRevision += 1
        selection = .dashboard
        resetDetail()
    }

    private func resetDetail() {
        detailRoute = nil
        detailCoordinator.path = NavigationPath()
    }
}

// MARK: - Deep Links

extension RootSplitCoordinator: HomeRootNavigating {
    func showHome() {
        selection = .dashboard
        resetDetail()
    }

    func showAllReviews() {
        selection = .recentReviews
        resetDetail()
    }

    /// Opens on top of the dashboard, so Back returns to it (as on iPhone,
    /// where links open on top of the Home).
    func show(_ route: HomeRoute) {
        showHome()
        detailCoordinator.push(route)
    }
}
