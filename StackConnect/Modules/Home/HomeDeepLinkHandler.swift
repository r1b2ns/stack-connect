import CoreSpotlight
import SwiftUI

// MARK: - Navigator

/// What a root layout must do to honor a deep link (widgets, local
/// notifications, the "re-import" alerts). Implemented by the compact Home
/// stack (`HomeCoordinator`) and by the regular-width split view
/// (`RootSplitCoordinator`), so both roots route links the same way.
@MainActor
protocol HomeRootNavigating: AnyObject {
    /// Back to the root screen (Home / Dashboard).
    func showHome()
    /// The cross-app reviews list.
    func showAllReviews()
    /// Settings › Privacy › Audit (the network audit list), on top of
    /// Settings so Back returns to it, as when reached from Settings.
    func showNetworkAudit()
    /// Resets the navigation and opens `route` on top of the root screen.
    func show(_ route: HomeRoute)
    /// Resets the navigation and opens `section` of `account` (its list
    /// screen), then `routes` on top of it, as if the user had tapped there.
    func showAccount(_ account: AccountModel, section: RootAccountSection, routes: [HomeRoute])
}

extension HomeCoordinator: HomeRootNavigating {
    func showHome() {
        path = NavigationPath()
    }

    func showAllReviews() {
        path = NavigationPath()
        navigateToAllReviews()
    }

    func showNetworkAudit() {
        path = NavigationPath()
        navigateToNetworkAudit()
    }

    func show(_ route: HomeRoute) {
        path = NavigationPath()
        push(route)
    }

    /// The section's list on top of the Home, then `routes`.
    func showAccount(_ account: AccountModel, section: RootAccountSection, routes: [HomeRoute]) {
        path = NavigationPath()
        if let root = section.compactRoute(for: account) {
            push(root)
        }
        routes.forEach(push)
    }
}

extension RootAccountSection {
    /// The screen that lists this section on iPhone (the split view's
    /// middle column builds the same screens in `RootAccountContentView`).
    /// `nil` for Users, which has no screen of its own outside the split view.
    func compactRoute(for account: AccountModel) -> HomeRoute? {
        switch self {
        case .apps:
            switch account.providerType {
            case .apple:      return .appList(account)
            case .googlePlay: return .googlePlayAppList(account)
            case .firebase:   return .firebaseProjectList(account)
            }
        case .users:        return nil
        case .devices:      return .devicesList(account)
        case .certificates: return .certificatesList(account)
        case .identifiers:  return .identifiersList(account)
        case .profiles:     return .profilesList(account)
        case .manage:       return .accountManagement(account)
        }
    }
}

// MARK: - Handler

/// Routes deep links (scheme `stackconnect`) into whichever root is on screen.
/// `app` and `review` links resolve their account first and open the screen of
/// its store (plan H7).
@MainActor
struct HomeDeepLinkHandler {

    let navigator: HomeRootNavigating
    var storage: PersistentStorable? = SwiftDataStorable.shared
    /// `networkAudit` gates the audit screen; while OFF its link opens Home.
    var featureFlags: FeatureFlags = .shared

    func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .home:
            navigator.showHome()
        case .reviews:
            navigator.showAllReviews()
        case .networkAudit:
            if featureFlags.isEnabled(.networkAudit) {
                navigator.showNetworkAudit()
            } else {
                navigator.showHome()
            }
        case .testFlight, .remoteConfig, .certificates:
            Task { await openLanding(for: link) }
        case .app, .review:
            Task { await open(link) }
        case let .reimport(accountId):
            Task { await openReimport(accountId: accountId) }
        }
    }

    /// Resolves an entry-point link (`testflight`, `remote-config`,
    /// `certificates`) and opens its landing. Without storage, the Home.
    func openLanding(for link: DeepLink) async {
        guard let storage,
              let landing = await DeepLinkResolver(storage: storage, featureFlags: featureFlags).landing(for: link)
        else {
            navigator.showHome()
            return
        }
        show(landing)
    }

    /// Opens `landing` in the root on screen.
    func show(_ landing: DeepLinkLanding) {
        switch landing {
        case .home:
            navigator.showHome()
        case .accountChooser:
            navigator.show(.accountsList)
        case let .accountSection(account, section):
            navigator.showAccount(account, section: section, routes: [])
        case let .testFlight(app, account):
            // As reached by hand: App List › App Detail › TestFlight.
            navigator.showAccount(account, section: .apps, routes: [
                .appDetail(app: app, account: account),
                .testFlight(appId: app.id, account: account)
            ])
        case let .remoteConfig(project, account):
            navigator.showAccount(account, section: .apps, routes: [
                .remoteConfig(project: project, account: account)
            ])
        }
    }

    private func openReimport(accountId: String) async {
        guard let storage,
              let account: AccountModel = try? await storage.fetch(AccountModel.self, id: accountId),
              FeatureFlags.shared.isVisible(account) else { return }
        // The accounts list opens the wizard on the re-import (`.reconnect`).
        navigator.show(.accountsList)
        ReimportRouter.shared.request(accountId: accountId, providerType: account.providerType)
    }

    private func open(_ link: DeepLink) async {
        guard let storage,
              let destination = await DeepLinkResolver(storage: storage).resolve(link) else { return }
        switch destination {
        case let .appStoreApp(app, account):
            navigator.show(.appDetail(app: app, account: account))
        case let .googlePlayApp(app, account):
            navigator.show(.googlePlayAppDetail(app: app, account: account))
        case let .review(review, appName, account, appId):
            navigator.show(.reviewDetail(review: review, appName: appName, account: account, appId: appId))
        }
    }
}

// MARK: - View Modifier

extension View {
    /// Feeds `onOpenURL` and the app-wide `DeepLinkRouter` into `navigator`.
    func homeDeepLinks(_ navigator: HomeRootNavigating) -> some View {
        modifier(HomeDeepLinksModifier(navigator: navigator))
    }
}

private struct HomeDeepLinksModifier: ViewModifier {
    let navigator: HomeRootNavigating

    func body(content: Content) -> some View {
        let handler = HomeDeepLinkHandler(navigator: navigator)
        content
            // Widget taps and other `stackconnect://` URLs go through the
            // router too, which tracks where the open came from. The router
            // sets `pending`, handled once by the `onReceive` below.
            .onOpenURL { url in
                DeepLinkRouter.shared.open(url, source: DeepLinkSource(openedURL: url))
            }
            // An app indexed in Spotlight (`AppSpotlightIndexer`): its item
            // identifier is the app's deep link.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let url = AppSpotlightIndexer.deepLinkURL(from: activity.userInfo) else { return }
                DeepLinkRouter.shared.open(url, source: .spotlight)
            }
            .onReceive(DeepLinkRouter.shared.$pending.compactMap { $0 }) { url in
                handler.handle(url)
                DeepLinkRouter.shared.pending = nil
            }
    }
}
