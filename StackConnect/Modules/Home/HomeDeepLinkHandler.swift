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
        case .app, .review:
            Task { await open(link) }
        case let .reimport(accountId):
            Task { await openReimport(accountId: accountId) }
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
            .onReceive(DeepLinkRouter.shared.$pending.compactMap { $0 }) { url in
                handler.handle(url)
                DeepLinkRouter.shared.pending = nil
            }
    }
}
