import SwiftUI

/// One fact of a `StackTrustCard`: `{icon} {title?} {text}`. The icon only
/// illustrates the text, so VoiceOver reads the text alone.
struct StackTrustItem: Identifiable, Hashable, Sendable {
    let systemImage: String
    /// A short bold lead, e.g. the method the fact is about.
    var title: String?
    let text: String

    var id: String { [systemImage, title ?? "", text].joined(separator: "|") }

    init(systemImage: String, title: String? = nil, text: String) {
        self.systemImage = systemImage
        self.title = title
        self.text = text
    }
}

/// A compact card of facts about how something sensitive is handled ("stays
/// on this device", "sent only to …"), with an optional footer such as a
/// "learn more" link.
///
/// Shared by the connection guide (its pages list what happens to the
/// credentials) and the trust panel of the App Store Connect email and
/// password screen, so both read the same way. In a `Form`, give its row a
/// clear background and zero insets so the card draws its own surface.
struct StackTrustCard<Footer: View>: View {

    enum Style {
        /// The grouped-row surface: blends with the screen's other cards.
        case plain
        /// A light tint of `tint`: stands out above a form's fields.
        case tinted
    }

    var title: String?
    let items: [StackTrustItem]
    var tint: Color = .accentColor
    var style: Style = .plain
    @ViewBuilder let footer: () -> Footer

    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 24

    init(
        title: String? = nil,
        items: [StackTrustItem],
        tint: Color = .accentColor,
        style: Style = .plain,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.items = items
        self.tint = tint
        self.style = style
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(items) { item in
                buildRow(item)
            }

            footer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var background: Color {
        switch style {
        case .plain:  return Color(.secondarySystemGroupedBackground)
        case .tinted: return tint.opacity(0.1)
        }
    }

    private func buildRow(_ item: StackTrustItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let title = item.title {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(item.title == nil ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

extension StackTrustCard where Footer == EmptyView {
    /// A card without a footer.
    init(title: String? = nil, items: [StackTrustItem], tint: Color = .accentColor, style: Style = .plain) {
        self.init(title: title, items: items, tint: tint, style: style, footer: { EmptyView() })
    }
}

/// A "learn more" button for a `StackTrustCard` footer, laid out like the
/// card's rows (same icon column) so it reads as part of the card. Tracking
/// belongs to the caller's action.
struct StackTrustCardButton: View {

    let title: String
    var systemImage: String = "info.circle"
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 24

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        // Inside a Form row: only the button reacts, not the whole card.
        .buttonStyle(.borderless)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            StackTrustCard(items: [
                StackTrustItem(systemImage: "lock.fill", text: "Saved only if you choose, and only in this device's Keychain"),
                StackTrustItem(systemImage: "icloud.slash", text: "Never synced through iCloud or sent to a StackConnect server")
            ], tint: .blue, style: .tinted) {
                StackTrustCardButton(title: "How Your Password Is Used") {}
            }
            StackTrustCard(title: "Per method", items: [
                StackTrustItem(systemImage: "key.fill", title: "API Key", text: "The .p8 private key signs each request on this device.")
            ])
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
