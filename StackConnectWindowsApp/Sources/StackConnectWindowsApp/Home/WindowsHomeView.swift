import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B4 / T-B5 / T-W29 / T-W32 — Home right-hand content.
//
// This view is now ONLY the right-hand pane of the two-pane sidebar design.
// The persistent shell (expiration banner + sidebar + divider) lives in
// RootView so it stays visible on every screen, including pushed routes such
// as "+ Add" and the apps list. WindowsHomeView simply renders the content
// that corresponds to the currently selected sidebar section:
//
//   │  content panel                  │
//   │  (dashboard / ASC list /        │
//   │   Firebase list / Settings)     │
//
// The selected sidebar section is persisted on the coordinator
// (`coordinator.sidebarSection`) so it survives route push/pop cycles that
// cause Home to be re-created (e.g. navigating to Customize Widgets and back).
//
// Sync and Refresh buttons live inside the Dashboard panel header alongside
// "Customize Widgets".

struct WindowsHomeView: View {
    let model: WindowsHomeModel
    let coordinator: WindowsHomeCoordinator

    /// Renders the right-hand content based on the current sidebar selection:
    /// - `nil` / `.home`     → dashboard (widgets + customize button)
    /// - `.appStoreConnect`  → App Store Connect accounts list (inline, no back button)
    /// - `.firebase`         → Firebase accounts list (inline, no back button)
    /// - `.settings`         → Settings placeholder (back clears sidebar selection)
    @ViewBuilder
    var body: some View {
        switch coordinator.sidebarSection {
        case .home, .none:
            dashboardPanel
        case .appStoreConnect:
            WindowsAccountsListView(
                provider: .apple,
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets,
                showBackButton: false
            )
        case .firebase:
            WindowsAccountsListView(
                provider: .firebase,
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets,
                showBackButton: false
            )
        case .settings:
            WindowsPlaceholderView(title: "Settings") {
                coordinator.sidebarSection = .home
            }
        }
    }

    // MARK: - Dashboard panel (nil section)

    /// Shown when no sidebar section is selected. Contains the sync banner,
    /// loading indicator, and the widgets container. The "Customize Widgets"
    /// button moves from the old toolbar into the dashboard header.
    private var dashboardPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Text("Dashboard")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    if model.state.syncState.isSyncing {
                        ProgressView()
                    }
                    Button("Sync") { model.triggerSync() }
                    Button("Refresh") { Task { await model.loadDashboard() } }
                        .disabled(model.state.isLoading)
                    Button("Customize Widgets") {
                        coordinator.push(.customizeWidgets)
                    }
                }
                syncBannerSlot
                loadingSlot
                widgetsSlot
                Spacer()
            }
            .padding(16)
        }
    }

    // MARK: - Sync banner slot (US-003)

    @ViewBuilder
    private var syncBannerSlot: some View {
        if model.state.syncState.isSyncing {
            WindowsSyncBannerView(syncState: model.state.syncState)
        }
    }

    // MARK: - Loading slot (US-012)

    @ViewBuilder
    private var loadingSlot: some View {
        if model.state.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading…")
                    .foregroundColor(.gray)
                Spacer()
            }
        }
    }

    // MARK: - Widgets slot (US-006 / US-007, updated T-W03)

    private var widgetsSlot: some View {
        WindowsWidgetContainerView(
            widgets: model.state.widgets,
            onAddWidgets: { coordinator.push(.customizeWidgets) },
            onSelectApp: { app in
                coordinator.push(
                    .appDetail(appId: app.id, accountId: app.accountId)
                )
            },
            onSelectReview: { item in
                coordinator.push(
                    .reviewDetail(
                        reviewId: item.review.id,
                        appId: item.app.id,
                        accountId: item.app.accountId
                    )
                )
            },
            onSeeMoreReviews: { app in
                if let app {
                    coordinator.push(
                        .ratingsAndReviews(
                            appId: app.id,
                            bundleId: app.bundleId,
                            accountId: app.accountId
                        )
                    )
                } else {
                    coordinator.push(.comingSoon(title: "All Reviews"))
                }
            }
        )
    }
}
