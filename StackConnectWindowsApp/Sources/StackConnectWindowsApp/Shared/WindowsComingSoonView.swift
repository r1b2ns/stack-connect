import SwiftCrossUI

// T-W04 — Centered "coming soon" placeholder view (design spec section 2.4).
//
// Used by the `comingSoon(title)` route to show a full-screen centered
// placeholder with a glyph, a title, and a "This feature is coming soon."
// message. Follows the existing Windows view pattern for user-facing strings
// (plain literals — the Windows package does not use `String(localized:)`).

struct WindowsComingSoonView: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("🚧")
                .font(.largeTitle)

            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text("This feature is coming soon.")
                .foregroundColor(.gray)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}
