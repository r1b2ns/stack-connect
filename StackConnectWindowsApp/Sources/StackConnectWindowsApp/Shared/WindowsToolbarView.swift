import SwiftCrossUI

// Phase 4 · B1b-2 · T-B3 — in-content toolbar row (design §2.4 step 1).
//
// SwiftCrossUI has no menu/title bar in v1, so the global Home commands live in
// a manual HStack at the top of the content: the app title on the left, "Sync"
// (US-004) and "Customize Widgets" (US-009) on the right.

struct WindowsToolbarView: View {
    let title: String
    let onSync: () -> Void
    let onCustomizeWidgets: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            Button("Sync", action: onSync)
            Button("Customize Widgets", action: onCustomizeWidgets)
        }
    }
}
