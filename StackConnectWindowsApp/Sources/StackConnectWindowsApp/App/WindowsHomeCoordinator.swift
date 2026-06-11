import Foundation
import SwiftCrossUI
import StackHomeCore

/// The section currently selected in the Home sidebar. `nil` means the
/// dashboard (root) is shown. Stored on the coordinator so the selection
/// survives view recreation during route push/pop cycles.
enum HomeSection: Hashable {
    case home
    case appStoreConnect
    case firebase
    case settings
}

// Phase 4 · B1b-2 · T-B1 / T-W03 — Windows navigation foundation.
//
// SwiftCrossUI 0.7 has no NavigationStack/NavigationSplitView, so navigation is
// a hand-rolled route stack the window redraws against (design §2.3). Home is
// the implicit root: an empty `routeStack` means "show Home"; the top of the
// stack is the current pushed screen. In-content "< Back" pops; there is no
// title-bar back button in v1.
//
// T-W03: the route set is extended with parameterized cases for the Apps &
// Reviews feature screens (design §2.2). The previous value-less `appDetail`,
// `reviewDetail`, and `allReviews` are replaced by parameterized variants that
// carry the identifiers the destination screens need. Account-management routes
// are preserved unchanged.

/// A destination pushed on top of Home. Home itself is the empty/root state, so
/// it is intentionally NOT a case here.
enum WindowsRoute: Hashable {

    // MARK: - Account management (unchanged)

    case accountsList(ProviderType)
    case addAccountOptions(ProviderType)
    case createAppleAccount
    case createFirebaseAccount
    case importScexport
    case settings
    case reimport
    case customizeWidgets

    // MARK: - Apps & Reviews (T-W03, design §2.2)

    /// Lists all active apps for an account. The `accountName` is passed through
    /// so the toolbar can display it without an async lookup (T-W06).
    case appsList(accountId: String, accountName: String)

    /// Lists archived apps for an account.
    case archivedApps(accountId: String)

    /// App detail screen. Parameterized with the app and owning account ids.
    case appDetail(appId: String, accountId: String)

    /// Generic "coming soon" placeholder for features not yet implemented.
    case comingSoon(title: String)

    /// Ratings & Reviews list for a specific app. Replaces the previous
    /// value-less `allReviews` case; the app context (id + bundle id + account)
    /// is required for filtering and API calls.
    case ratingsAndReviews(appId: String, bundleId: String, accountId: String)

    /// Single review detail. Parameterized with review, app, and account ids.
    case reviewDetail(reviewId: String, appId: String, accountId: String)

    /// Compose or edit a developer response to a review. `existingReplyBody` is
    /// non-nil when editing an already-published response. `existingResponseId`
    /// carries the server-assigned response identifier in edit mode so the upsert
    /// replaces the existing reply instead of creating a duplicate (AC-W13-3).
    case replyComposer(reviewId: String, accountId: String, existingReplyBody: String?, existingResponseId: String?)

    /// Confirmation dialog before deleting a developer response.
    case deleteReplyConfirm(reviewId: String, responseId: String, accountId: String)

    /// Confirmation screen before archiving an app (T-W06, AC-W04).
    /// Pushed as a route (TC-072: not an alert/sheet). The `appName` is passed
    /// through so the confirmation screen can display it without a model lookup.
    case archiveAppConfirm(appId: String, appName: String)

    /// Confirmation screen before restoring an archived app (T-W07, AC-W04-4).
    /// Pushed as a route (TC-072: not an alert/sheet). The `appName` is passed
    /// through so the confirmation screen can display it without a model lookup.
    case restoreAppConfirm(appId: String, appName: String)

    /// Confirmation screen before archiving an app FROM the App Detail screen
    /// (T-W12, AC-W09-3). Uses `WindowsAppDetailModel` instead of
    /// `WindowsAppsListModel`. Pushed as a route (TC-072: not an alert/sheet).
    case archiveAppDetailConfirm(appId: String, appName: String, accountId: String)
}

/// Holds the Windows navigation route stack and the push/pop operations the
/// views drive. An `ObservableObject` so the window redraws when the stack
/// changes (SwiftCrossUI observes `@Published` via the owning `@State`).
@MainActor
final class WindowsHomeCoordinator: SwiftCrossUI.ObservableObject {
    /// The pushed-route stack. Empty = Home (root).
    //
    // `Published`/`ObservableObject` are qualified because on the macOS host
    // Foundation re-exports Combine's same-named symbols; on Windows there is no
    // Combine so the qualification is harmless.
    @SwiftCrossUI.Published private(set) var routeStack: [WindowsRoute] = []

    /// The sidebar section currently selected on the Home screen. `nil` shows
    /// the dashboard. Stored here so the selection persists across view
    /// re-renders triggered by route pushes/pops.
    @SwiftCrossUI.Published var sidebarSection: HomeSection? = .home

    /// The screen currently shown, or `nil` when at Home.
    var current: WindowsRoute? { routeStack.last }

    /// Whether the window is showing Home (nothing pushed).
    var isAtRoot: Bool { routeStack.isEmpty }

    func push(_ route: WindowsRoute) {
        routeStack.append(route)
    }

    func pop() {
        guard !routeStack.isEmpty else { return }
        routeStack.removeLast()
    }

    func popToRoot() {
        routeStack.removeAll()
    }
}
