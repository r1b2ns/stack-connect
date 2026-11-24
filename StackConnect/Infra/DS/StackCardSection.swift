import SwiftUI

// MARK: - Card section

/// An inset-grouped section drawn by hand, for screens laid out in a
/// `ScrollView` (side-by-side cards on iPad, where a `List` can't put two
/// sections next to each other): `HEADER ——— {trailing}` over a rounded card,
/// with an optional footnote below. Rows go inside the card, separated with
/// `StackCardDivider`.
struct StackCardSection<Content: View, Trailing: View>: View {

    var title: String?
    var footer: String?
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(
        title: String? = nil,
        footer: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title.uppercased())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    trailing()
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 16)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension StackCardSection where Trailing == EmptyView {
    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, footer: footer, trailing: { EmptyView() }, content: content)
    }
}

/// The hairline between two rows of a `StackCardSection`, inset like a List's.
struct StackCardDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

// MARK: - Code block

/// Monospaced text on a dark surface: request / response bodies and export
/// previews.
struct StackCodeBlock: View {

    let text: String
    var lineLimit: Int?

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 12, design: .monospaced))
            .lineSpacing(4)
            .foregroundStyle(Color(red: 0.95, green: 0.95, blue: 0.97))
            .lineLimit(lineLimit)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(red: 0.11, green: 0.11, blue: 0.118), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Warning card

/// A warm notice: what can't be undone or what always stays masked.
/// `{icon} {title?} / {text}` on a light orange surface.
struct StackWarningCard<Extra: View>: View {

    var systemImage: String = "exclamationmark.shield.fill"
    var title: String?
    let text: String
    @ViewBuilder let extra: () -> Extra

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                Text(text)
                    .font(title == nil ? .subheadline : .footnote)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var background: Color {
        colorScheme == .dark ? Color.orange.opacity(0.18) : Color(red: 1, green: 0.957, blue: 0.898)
    }

    private var foreground: Color {
        colorScheme == .dark ? Color(red: 1, green: 0.84, blue: 0.68) : Color(red: 0.36, green: 0.153, blue: 0)
    }
}

extension StackWarningCard where Extra == EmptyView {
    init(systemImage: String = "exclamationmark.shield.fill", title: String? = nil, text: String) {
        self.init(systemImage: systemImage, title: title, text: text, extra: { EmptyView() })
    }
}

// MARK: - Big buttons

/// The 50pt full-width actions at the bottom of a sheet: `.filled` (accent)
/// or `.plain` (card surface, accent text).
struct StackBigButtonStyle: ButtonStyle {

    enum Kind {
        case filled
        case plain
    }

    var kind: Kind = .filled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(kind == .filled ? Color.white : Color.accentColor)
            .background(
                kind == .filled ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            StackCardSection(title: "Summary", footer: "Footnote") {
                Text(verbatim: "Row").padding(16)
                StackCardDivider()
                Text(verbatim: "Row").padding(16)
            }
            StackCodeBlock(text: "{\n  \"data\": []\n}")
            StackWarningCard(text: "Reducing to 7 days deletes 12 events now.")
            Button("Export") {}.buttonStyle(StackBigButtonStyle())
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}
