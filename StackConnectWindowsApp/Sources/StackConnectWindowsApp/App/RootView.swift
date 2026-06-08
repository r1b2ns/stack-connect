import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B2/T-B4 — the window's root view + route switch.
//
// Owns the observed state (the core adapter and the navigation coordinator) and
// renders the current screen: Home when the route stack is empty, otherwise the
// pushed destination. The pushed destinations are labeled placeholders in v1
// (T-D3 builds them out) but navigation — push from Home, "< Back" to pop — is
// fully functional so the shell is testable end-to-end.

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

    /// Resolves a pushed route to its destination (US-011 AC-1). Customize
    /// Widgets (T-C3) is a real full-screen screen (US-008); every other v1
    /// route is a labeled placeholder with a working "< Back" (design D3), with
    /// `reimport` rendered as a DISABLED placeholder (design D7 — no live Apple
    /// sync on Windows v1).
    ///
    /// The switch is exhaustive (no `default`) so adding a route to
    /// `WindowsRoute` is a compile error until a destination is wired here.
    @ViewBuilder
    private func destination(for route: WindowsRoute) -> some View {
        switch route {
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
        case .appDetail:
            WindowsPlaceholderView(title: "App Detail") { coordinator.pop() }
        case .reviewDetail:
            WindowsPlaceholderView(title: "Review Detail") { coordinator.pop() }
        case .allReviews:
            WindowsPlaceholderView(title: "All Reviews") { coordinator.pop() }
        }
    }
}
