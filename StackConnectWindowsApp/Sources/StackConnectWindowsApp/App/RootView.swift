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

    /// Placeholder destinations for v1 (T-D3 replaces these with real screens).
    /// Each keeps a working "< Back" so push/pop is verifiable now.
    private func destination(for route: WindowsRoute) -> AnyView {
        AnyView(
            VStack(spacing: 16) {
                WindowsBackButtonView { coordinator.pop() }
                Spacer()
                Text(title(for: route))
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Coming soon")
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        )
    }

    private func title(for route: WindowsRoute) -> String {
        switch route {
        case .accountsList(let provider): return provider.displayName
        case .settings: return "Settings"
        case .appDetail: return "App Detail"
        case .reviewDetail: return "Review Detail"
        case .allReviews: return "All Reviews"
        case .reimport: return "Re-import"
        case .customizeWidgets: return "Customize Widgets"
        }
    }
}
