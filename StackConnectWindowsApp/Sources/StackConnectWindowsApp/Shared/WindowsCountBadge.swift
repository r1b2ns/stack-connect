import SwiftCrossUI

// T-W04 — A small numeric badge for displaying item counts (design spec
// section 2.4 component inventory).
//
// Used by sections like "Recent Reviews (5)" or "Reviews (50)" to show
// a parenthesized count next to a section title. Renders in secondary
// (gray) color to match the existing widget header count style.
//
// The count is hidden when zero, matching the pattern in
// `WindowsWidgetHeaderView`.

struct WindowsCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("(\(count))")
                .foregroundColor(.gray)
        }
    }
}
