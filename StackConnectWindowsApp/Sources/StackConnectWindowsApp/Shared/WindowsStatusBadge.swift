import SwiftCrossUI
import StackHomeCore

// T-W04 — Colored pill showing an app's App Store status (design spec section
// 2.4 component inventory, section 2.6 WinUI adaptations A-04).
//
// SF-symbol colored tiles are not available on Windows. Instead, render a
// colored rounded-rect background + status text as a pill badge. The color
// is derived from the existing `AppStoreState.color` (an `AppStoreStateColor`
// enum), mapped to SwiftCrossUI `Color` values.
//
// Per AC-W01-6/7/8:
//   - Ready for Sale       = green
//   - Pending Dev Release   = yellow
//   - Prepare for Submission = blue
//
// The view also supports a colored-text fallback (per A-04): the text is
// rendered in the mapped color on a subtle background so it is readable
// regardless of WinUI theme limitations.

struct WindowsStatusBadge: View {
    let state: AppStoreState

    var body: some View {
        Text(state.displayName)
            .foregroundColor(resolvedColor)
            .padding(4)
            .background(resolvedColor.opacity(0.15))
            .cornerRadius(4)
    }

    /// Maps `AppStoreStateColor` to a SwiftCrossUI `Color`.
    private var resolvedColor: Color {
        switch state.color {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}
