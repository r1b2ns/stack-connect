import SwiftCrossUI

// T-W04 — A glyph/label + chevron row for option lists (design spec section
// 2.4 component inventory).
//
// Used by App Detail option lists and similar navigation menus. No SF Symbols
// are available on Windows — the glyph is a text/emoji string passed in by
// the caller. The row is tappable: tapping triggers the provided action
// closure. A trailing ">" chevron indicates navigability.

struct WindowsOptionRow: View {
    let glyph: String
    let label: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(glyph)
            Text(label)
            Spacer()
            Text(">")
                .foregroundColor(.gray)
        }
        .padding(8)
        .background(Color(white: 0.94))
        .cornerRadius(6)
        .onTapGesture(perform: action)
    }
}
