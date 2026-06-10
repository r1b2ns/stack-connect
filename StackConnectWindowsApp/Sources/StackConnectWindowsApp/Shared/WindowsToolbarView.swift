import SwiftCrossUI

// Phase 4 · B1b-2 · T-B3 / T-W29 — in-content toolbar row (design §2.4 step 1).
//
// SwiftCrossUI has no menu/title bar in v1, so the global Home commands live in
// a manual HStack at the top of the content: the app title on the left, "Sync"
// (US-004), "Refresh" (US-W17 AC-W17-2), and "Customize Widgets" (US-009) on
// the right.
//
// T-D4 (design §2.9): the action labels adapt to the available width. The
// toolbar does not read geometry itself — `WindowsHomeView` wraps it in a
// scoped `GeometryReader` and passes in the resolved `WindowsLayoutTier`, so the
// label choice is a pure function of the tier and is unit-testable without a
// GUI.
//
// T-W29: added `onRefresh` — an explicit Refresh button that reloads the
// dashboard (calls `loadDashboard()` via the caller's closure). This matches
// the pattern used by all other Windows screens (WindowsAppsListView,
// WindowsArchivedAppsView, WindowsAppDetailView, WindowsRatingsReviewsView)
// which each expose a `Button("Refresh")` in their toolbars (TC-070: explicit
// button, NO pull-to-refresh — SwiftCrossUI has none). "Refresh" is short like
// "Sync", so it stays whole at every tier.

struct WindowsToolbarView: View {
    let title: String
    /// The resolved responsive tier driving label length (design §2.9).
    let tier: WindowsLayoutTier
    let onSync: () -> Void
    /// Reloads the dashboard data (US-W17 AC-W17-2). Triggers `loadDashboard()`
    /// via the caller's closure; the loading state is driven by the core's
    /// `isLoading` flag (shown/hidden by the parent's `loadingSlot`).
    let onRefresh: () -> Void
    let onCustomizeWidgets: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            Button("Refresh", action: onRefresh)
            Button("Sync", action: onSync)
            Button(customizeLabel, action: onCustomizeWidgets)
        }
    }

    /// "Customize Widgets" (regular ≥860) → "Customize" (compact 680–859) →
    /// "Widgets" (abbreviated <680), so the toolbar never overflows the narrow
    /// window. "Sync" and "Refresh" are already short, so they stay whole at
    /// every tier.
    private var customizeLabel: String {
        switch tier {
        case .regular:     return "Customize Widgets"
        case .compact:     return "Customize"
        case .abbreviated: return "Widgets"
        }
    }
}
