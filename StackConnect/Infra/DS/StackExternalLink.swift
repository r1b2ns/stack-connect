import SwiftUI

/// A link to a web page outside the app, as data: what `StackExternalLink`
/// shows, where it goes, and the `button` reported when it opens.
struct StackExternalLinkItem: Identifiable, Hashable, Sendable {
    let title: String
    let systemImage: String
    let url: URL
    /// Reported when the link is opened (never the URL).
    let button: AnalyticsButton

    var id: URL { url }
}

/// A link to a web page outside the app: `{icon} {title} ↗`, opened in the
/// browser like the app's other external links (`Link`), and reported as
/// `button` on `screen` when opened (never the URL itself).
///
/// Used by the connection guide (source code, privacy policy) and "How Your
/// Password Is Used" (source file, privacy policy).
struct StackExternalLink: View {

    let title: String
    let systemImage: String
    let destination: URL
    let button: AnalyticsButton
    let screen: AnalyticsScreen

    /// A fixed icon column, so titles line up whatever the glyph's width.
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 24

    var body: some View {
        Link(destination: destination) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right.square")
                    .font(.subheadline)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .trackOpenURL(button, on: screen)
    }
}

extension StackExternalLink {
    /// The link described by `item`, reported on `screen`.
    init(_ item: StackExternalLinkItem, screen: AnalyticsScreen) {
        self.init(title: item.title, systemImage: item.systemImage, destination: item.url, button: item.button, screen: screen)
    }
}

#Preview {
    List {
        StackExternalLink(
            title: "Privacy Policy",
            systemImage: "hand.raised.fill",
            destination: ProjectLinks.privacyPolicy,
            button: .privacyPolicy,
            screen: .connectionGuide
        )
    }
}
