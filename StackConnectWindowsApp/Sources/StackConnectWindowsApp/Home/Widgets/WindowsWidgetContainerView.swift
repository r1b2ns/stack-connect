import SwiftCrossUI
import StackHomeCore

// Phase 4 · B1b-2 · T-C1 — the Home widgets section container (US-006, design
// §2.4 item 4 / §2.5).
//
// This is the slot that sits BELOW the provider cards + Settings in
// `WindowsHomeView`. It is a pure function of the active widgets from the shared
// core (`HomeViewModel` → `WindowsHomeModel.state.widgets`):
//
//   • no active widgets  → a single centered empty-state card
//                          (`WindowsWidgetsEmptyStateView`), whose "Add Widgets"
//                          button pushes `.customizeWidgets` (AC-1, AC-2).
//   • one or more widgets → a VStack of per-widget cards in stored order.
//
// SwiftCrossUI 0.7 has no `LazyVGrid`, so this is a plain VStack — the parent
// `WindowsHomeView` already wraps the whole Home in a ScrollView, so the section
// scrolls with the rest of the content (design §2.4: the widgets are part of the
// single vertical scroll, never their own scroll region).
//
// SCOPE (T-C2): the three concrete widget views (In Review / Awaiting Release /
// Recent Reviews) are now wired in here, replacing the T-C1 placeholder slot.
// Each active widget is dispatched on its `kind` to the matching SwiftCrossUI
// view, fed the widget's typed core result data + `isLoading`, and routed
// through the coordinator callbacks (US-007 AC-1/AC-6/AC-7).

struct WindowsWidgetContainerView: View {

    /// The active widgets from the shared core, in stored order.
    let widgets: [any HomeWidget]

    /// Pushes the Customize Widgets route. Invoked by the empty-state card's
    /// "Add Widgets" button (US-006 AC-2).
    let onAddWidgets: () -> Void

    /// Pushes the App Detail route when an In Review / Awaiting Release row is
    /// tapped (US-007 AC-6 — v1 placeholder).
    let onSelectApp: (AppModel) -> Void

    /// Pushes the Review Detail route when a Recent Reviews row is tapped
    /// (US-007 AC-6 — v1 placeholder).
    let onSelectReview: (HomeRecentReview) -> Void

    /// Pushes the All Reviews route from the Recent Reviews "See more" link
    /// (US-007 AC-7 — v1 placeholder).
    let onSeeMoreReviews: () -> Void

    var body: some View {
        // The empty flag is derived by a pure helper so the "empty drives empty
        // state" branch (TC-030) is unit-testable on the Mac host without a GUI.
        if widgetsSectionIsEmpty(widgets) {
            WindowsWidgetsEmptyStateView(onAddWidgets: onAddWidgets)
        } else {
            VStack(spacing: 12) {
                ForEach(widgets, id: \.id) { widget in
                    widgetView(for: widget)
                }
            }
        }
    }

    // MARK: - Per-widget dispatch (T-C2)

    /// Dispatches a single active widget on its concrete type to the matching
    /// Windows view, passing the widget's typed result data + `isLoading` and
    /// wiring its taps through the coordinator callbacks. The downcast mirrors
    /// the iOS `HomeWidgetViewFactory`: the registry pairs each `kind` with its
    /// concrete data object, so a mismatch (not expected) renders nothing.
    @ViewBuilder
    private func widgetView(for widget: any HomeWidget) -> some View {
        switch widget.kind {
        case .inReview:
            if let widget = widget as? InReviewWidget {
                WindowsInReviewWidgetView(
                    data: widget.data,
                    isLoading: widget.isLoading,
                    onSelectApp: onSelectApp
                )
            }
        case .awaitingRelease:
            if let widget = widget as? AwaitingReleaseWidget {
                WindowsAwaitingReleaseWidgetView(
                    data: widget.data,
                    isLoading: widget.isLoading,
                    onSelectApp: onSelectApp
                )
            }
        case .recentReviews:
            if let widget = widget as? RecentReviewsWidget {
                WindowsRecentReviewsWidgetView(
                    data: widget.data,
                    isLoading: widget.isLoading,
                    onSelectReview: onSelectReview,
                    onSeeMore: onSeeMoreReviews
                )
            }
        }
    }
}

// MARK: - Pure section-state helper (GUI-free, unit-testable)

/// Whether the widgets section should render its empty state.
///
/// Pulled out of the view so the "no active widgets ⇒ empty state" rule (US-006
/// AC-1, TC-030) can be asserted in a plain unit test on the macOS host without
/// a window. `true` ⇒ show the empty-state card; `false` ⇒ render the widget
/// cards.
func widgetsSectionIsEmpty(_ widgets: [any HomeWidget]) -> Bool {
    widgets.isEmpty
}
