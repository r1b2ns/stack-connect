import SwiftCrossUI

// Phase 4 · B1b-2 · T-C1 — the widgets empty-state card (US-006, design §2.5).
//
// Rendered by `WindowsWidgetContainerView` when there are NO active widgets.
// A single centered radius-8 card: a grid-glyph substitute ("[#]" — SwiftCrossUI
// 0.7 has no SF Symbols, design §2.8), a bold "No widgets yet" headline, a
// one-line description, and an "Add Widgets" button that pushes the Customize
// Widgets route on the coordinator (AC-2). The view is purely presentational —
// it takes the tap action as a closure so the container owns the routing and the
// card stays GUI-only/reusable.

struct WindowsWidgetsEmptyStateView: View {

    /// Invoked when the user taps "Add Widgets". Wired by the container to push
    /// `.customizeWidgets` on the coordinator (US-006 AC-2).
    let onAddWidgets: () -> Void

    /// Corner radius shared with the provider/widget cards (design §2.4: radius 8).
    private let cardRadius = 8

    var body: some View {
        VStack(spacing: 8) {
            // Grid-icon substitute — no SF Symbols / no Grid glyph in
            // SwiftCrossUI 0.7, so the icon table (design §2.8) maps the grid
            // icon to the text token "[#]".
            Text("[#]")
                .fontWeight(.bold)
                .foregroundColor(.gray)

            Text("No widgets yet")
                .fontWeight(.semibold)

            Text("Add widgets to keep an eye on your apps right from here.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button("Add Widgets", action: onAddWidgets)
        }
        // Centered content inside a full-width card (design §2.5: single centered
        // empty-state card).
        .frame(maxWidth: .infinity)
        .padding(16)
        // Card chrome: ~8% gray fill + 1px border, radius 8, no drop shadow
        // (design §2.4 widget card spec).
        .background(Color(white: 0.92).opacity(0.08))
        .cornerRadius(cardRadius)
        // Stroke MUST live in `.background` (not `.overlay`): on the AppKit
        // backend an overlaid stroke becomes a sibling path view on top of the
        // card that swallows clicks on any interactive child. Behind the
        // translucent fill the border still shows through.
        .background {
            RoundedRectangle(cornerRadius: Double(cardRadius))
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }
}
