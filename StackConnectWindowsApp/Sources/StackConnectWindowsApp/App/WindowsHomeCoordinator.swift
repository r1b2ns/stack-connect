import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B1 — Windows navigation foundation.
//
// SwiftCrossUI 0.7 has no NavigationStack/NavigationSplitView, so navigation is
// a hand-rolled route stack the window redraws against (design §2.3). Home is
// the implicit root: an empty `routeStack` means "show Home"; the top of the
// stack is the current pushed screen. In-content "< Back" pops; there is no
// title-bar back button in v1.

/// A destination pushed on top of Home. Home itself is the empty/root state, so
/// it is intentionally NOT a case here.
enum WindowsRoute: Hashable {
    case accountsList(ProviderType)
    case settings
    case appDetail
    case reviewDetail
    case allReviews
    case reimport
    case customizeWidgets
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
