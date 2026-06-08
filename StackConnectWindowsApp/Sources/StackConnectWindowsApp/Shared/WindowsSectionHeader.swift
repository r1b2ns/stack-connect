import SwiftCrossUI

// T-W04 — Section title row with an optional trailing "See All" action button
// (design spec section 2.4 component inventory).
//
// Used by App Detail and other screens that group content into labeled
// sections. When `onSeeAll` is provided, a trailing "See All" button appears
// on the right side of the row.

struct WindowsSectionHeader: View {
    let title: String
    let onSeeAll: (() -> Void)?

    init(title: String, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            if let action = onSeeAll {
                Button("See All", action: action)
            }
        }
    }
}
