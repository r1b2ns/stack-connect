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
// SCOPE (T-C1): only the container + empty state are real. The three concrete
// widget views (In Review / Awaiting Release / Recent Reviews) are T-C2; here
// each active widget renders a minimal, clearly-marked placeholder card carrying
// just the widget's kind header, as a slot T-C2 will replace.

struct WindowsWidgetContainerView: View {

    /// The active widgets from the shared core, in stored order.
    let widgets: [any HomeWidget]

    /// Pushes the Customize Widgets route. Invoked by the empty-state card's
    /// "Add Widgets" button (US-006 AC-2).
    let onAddWidgets: () -> Void

    /// Corner radius shared with the provider/empty-state cards (design §2.4:
    /// radius 8).
    private let cardRadius = 8

    var body: some View {
        // The empty flag is derived by a pure helper so the "empty drives empty
        // state" branch (TC-030) is unit-testable on the Mac host without a GUI.
        if widgetsSectionIsEmpty(widgets) {
            WindowsWidgetsEmptyStateView(onAddWidgets: onAddWidgets)
        } else {
            VStack(spacing: 12) {
                ForEach(widgets, id: \.id) { widget in
                    placeholderCard(for: widget)
                }
            }
        }
    }

    // MARK: - Per-widget placeholder slot (T-C2 replaces this)

    /// A minimal placeholder card for a single active widget: the kind glyph +
    /// header, plus a clearly-marked TODO note. T-C2 swaps this out for the real
    /// In Review / Awaiting Release / Recent Reviews views. Kept here so the
    /// non-empty branch is wired end-to-end (US-007 AC-1: each widget renders in
    /// stored order in a card container; the actual content lands in T-C2).
    private func placeholderCard(for widget: any HomeWidget) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(glyph(for: widget.kind))
                    .fontWeight(.bold)
                Text(widget.kind.displayName)
                    .fontWeight(.semibold)
                Spacer()
            }
            HStack {
                // TODO: T-C2 — replace with the real widget view
                // (loading / empty / data states).
                Text("Widget content coming soon")
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(white: 0.92).opacity(0.08))
        .cornerRadius(cardRadius)
        .overlay {
            RoundedRectangle(cornerRadius: Double(cardRadius))
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }

    // MARK: - Icon substitution (design §2.8)

    /// Text/glyph icon substitute per widget kind (no SF Symbols in SwiftCrossUI
    /// 0.7, design §2.8). Mirrors the placeholder glyphs the Home shell used
    /// before this container existed.
    private func glyph(for kind: HomeWidgetKind) -> String {
        switch kind {
        case .inReview:        return "🔍"
        case .awaitingRelease: return "📤"
        case .recentReviews:   return "💬"
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
