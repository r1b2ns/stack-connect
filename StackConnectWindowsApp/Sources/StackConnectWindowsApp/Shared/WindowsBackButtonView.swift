import SwiftCrossUI

// Phase 4 · B1b-2 · T-B3 — in-content "< Back" (design §2.3).
//
// SwiftCrossUI 0.7 has no NavigationStack, so Back is a plain button that pops
// the route stack. Rendered at the top-left of every pushed screen.

struct WindowsBackButtonView: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button("< Back", action: onBack)
            Spacer()
        }
    }
}
