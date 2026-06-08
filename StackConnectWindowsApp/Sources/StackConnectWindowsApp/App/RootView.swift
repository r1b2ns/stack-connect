import SwiftCrossUI
import StackHomeCore

// Phase 4 · Block F · T-F16 / T-W03 — the window's root view + route switch.
//
// Owns the observed state (the core adapter and the navigation coordinator) and
// renders the current screen: Home when the route stack is empty, otherwise the
// pushed destination. Account management routes (accounts list, add options,
// create Apple/Firebase, import .scexport) are wired to real views.
//
// T-W03: the Apps & Reviews routes (appsList, archivedApps, appDetail,
// comingSoon, ratingsAndReviews, reviewDetail, replyComposer,
// deleteReplyConfirm) are now parameterized per §2.2. Until the real feature
// views land (T-W06, T-W12, T-W19, T-W23 etc.), every new route renders a
// `WindowsPlaceholderView` with the route name/title. The switch remains
// exhaustive (no `default`) so new routes are compile-safe.

struct RootView: View {
    /// Observed core adapter (state + intents).
    @State private var model: WindowsHomeModel
    /// Observed navigation coordinator (route stack).
    @State private var coordinator: WindowsHomeCoordinator

    init(model: WindowsHomeModel) {
        _model = State(wrappedValue: model)
        _coordinator = State(wrappedValue: model.coordinator)
    }

    var body: some View {
        currentScreen
            .task {
                // Offline-first: load the dashboard from SQLite on first appear.
                await model.loadDashboard()
            }
    }

    @ViewBuilder
    private var currentScreen: some View {
        if let route = coordinator.current {
            destination(for: route)
        } else {
            WindowsHomeView(model: model, coordinator: coordinator)
        }
    }

    /// Resolves a pushed route to its destination. Account management screens
    /// (T-F07, T-F08, T-F10, T-F11, T-F13) are real views; `reimport` is
    /// intentionally disabled (no live Apple sync on Windows v1); Apps & Reviews
    /// routes (T-W03) are placeholder-wired until their real views land.
    ///
    /// The switch is exhaustive (no `default`) so adding a route to
    /// `WindowsRoute` is a compile error until a destination is wired here.
    @ViewBuilder
    private func destination(for route: WindowsRoute) -> some View {
        switch route {

        // MARK: Account management (unchanged)

        case .customizeWidgets:
            WindowsCustomizeWidgetsView(model: model, coordinator: coordinator)

        // D7: re-import is intentionally unavailable on Windows v1.
        case .reimport:
            WindowsPlaceholderView(
                title: "Re-import",
                isDisabled: true,
                onBack: { coordinator.pop() }
            )

        // T-F07: real accounts list screen (US-W01 / US-W06).
        case .accountsList(let provider):
            WindowsAccountsListView(
                provider: provider,
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets
            )
        case .addAccountOptions(let provider):
            WindowsAddAccountOptionsView(provider: provider, coordinator: coordinator)
        // T-F10: real create Apple account form (US-W03).
        case .createAppleAccount:
            WindowsCreateAppleAccountView(
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets
            )
        case .createFirebaseAccount:
            WindowsCreateFirebaseAccountView(
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets
            )
        // T-F13: real import .scexport screen (US-W05).
        case .importScexport:
            WindowsImportAccountView(
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets
            )
        case .settings:
            WindowsPlaceholderView(title: "Settings") { coordinator.pop() }

        // MARK: Apps & Reviews placeholders (T-W03)

        case .appsList:
            WindowsPlaceholderView(title: "Apps List") { coordinator.pop() }

        case .archivedApps:
            WindowsPlaceholderView(title: "Archived Apps") { coordinator.pop() }

        case .appDetail:
            WindowsPlaceholderView(title: "App Detail") { coordinator.pop() }

        case .comingSoon(let title):
            WindowsPlaceholderView(title: title) { coordinator.pop() }

        case .ratingsAndReviews:
            WindowsPlaceholderView(title: "Ratings & Reviews") { coordinator.pop() }

        case .reviewDetail:
            WindowsPlaceholderView(title: "Review Detail") { coordinator.pop() }

        case .replyComposer:
            WindowsPlaceholderView(title: "Reply Composer") { coordinator.pop() }

        case .deleteReplyConfirm:
            WindowsPlaceholderView(title: "Delete Reply") { coordinator.pop() }
        }
    }
}
