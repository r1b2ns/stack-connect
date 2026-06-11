import Foundation
import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-B4 / T-B5 / T-W29 / T-W32 — Sidebar-style Home layout.
//
// Replaced the central card-grid layout with a two-pane sidebar design:
//
//   ┌─────────────────────────────────────────────┐
//   │ [expiration alert — full width, conditional]│
//   ├─────────────────────────────────────────────┤
//   │  🏠 Home     │  Dashboard  [Sync][Refresh]  │
//   │  ─────────   │  [Customize Widgets]         │
//   │  App Store   │                              │
//   │  Connect  ←  │  content panel               │
//   │  ─────────   │  (dashboard / ASC list /     │
//   │  🔥 Firebase │   Firebase list / Settings)  │
//   │  ─────────   │                              │
//   │  ⚙ Settings  │                              │
//   │              │                              │
//   └──────────────┴──────────────────────────────┘
//    200px fixed     flexible
//
// The selected sidebar section is persisted on the coordinator
// (`coordinator.sidebarSection`) so it survives route push/pop cycles that
// cause Home to be re-created (e.g. navigating to Customize Widgets and back).
//
// Sync and Refresh buttons live inside the Dashboard panel header alongside
// "Customize Widgets". There is no top bar; the expiration alert sits above
// the sidebar/content split.

struct WindowsHomeView: View {
    let model: WindowsHomeModel
    let coordinator: WindowsHomeCoordinator

    var body: some View {
        VStack(spacing: 0) {
            expirationAlertSlot
            HStack(spacing: 0) {
                sidebarPanel
                Divider()
                contentPanel
            }
        }
    }

    // MARK: - Expiration alert slot (US-005)

    /// Full-width expiration banner rendered between the top bar and the
    /// sidebar/content split. The banner view itself renders nothing when
    /// no alert is active.
    @ViewBuilder
    private var expirationAlertSlot: some View {
        WindowsAlertBannerView(model: model, coordinator: coordinator)
    }

    // MARK: - Sidebar panel (200px fixed)

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            buildSidebarItem(
                section: .home,
                glyph: "🏠",
                title: "Home",
                tint: .purple
            )
            Divider()
                .padding(.vertical, 4)
            buildSidebarItem(
                section: .appStoreConnect,
                glyph: "ASC",
                title: "App Store Connect",
                tint: .blue
            )
            buildSidebarItem(
                section: .firebase,
                glyph: "🔥",
                title: "Firebase",
                tint: .orange
            )
            Divider()
                .padding(.vertical, 4)
            buildSidebarItem(
                section: .settings,
                glyph: "⚙",
                title: "Settings",
                tint: .gray
            )
            Spacer()
        }
        .padding(8)
        .frame(width: 200)
        .background(Color.gray.opacity(0.04))
    }

    private func buildSidebarItem(
        section: HomeSection,
        glyph: String,
        title: String,
        tint: Color
    ) -> some View {
        let isSelected = coordinator.sidebarSection == section
        return HStack(spacing: 8) {
            Text(glyph)
                .fontWeight(.bold)
                .foregroundColor(tint)
            Text(title)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? tint.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .onTapGesture { coordinator.sidebarSection = section }
    }

    // MARK: - Content panel (flexible)

    /// Renders the right-hand panel based on the current sidebar selection:
    /// - `nil`               → dashboard (widgets + customize button)
    /// - `.appStoreConnect`  → App Store Connect accounts list (inline, no back button)
    /// - `.firebase`         → Firebase accounts list (inline, no back button)
    /// - `.settings`         → Settings placeholder (back clears sidebar selection)
    @ViewBuilder
    private var contentPanel: some View {
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
