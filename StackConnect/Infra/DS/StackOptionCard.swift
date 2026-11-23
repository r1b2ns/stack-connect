import SwiftUI

/// One option of a "pick how to continue" choice, as a card:
/// `{icon tile} {title / message} {chevron}`.
///
/// Render it as the `label` of a `Button` in its own `Form` section, so every
/// option gets the same card and the same weight (no option is promoted over
/// another). The tap and its tracking belong to the caller. Used by Add
/// Account's method chooser.
struct StackOptionCard: View {

    let systemImage: String
    var tint: Color = .accentColor
    let title: String
    let message: String

    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            StackIconTile(systemName: systemImage, color: tint, size: tileSize, font: .title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Form {
        Section {
            Button {} label: {
                StackOptionCard(systemImage: "key.fill", title: "Use an API key", message: "Add an App Store Connect API key: its .p8 file, Key ID and Issuer ID.")
            }
        }
        Section {
            Button {} label: {
                StackOptionCard(systemImage: "person.badge.key.fill", title: "Sign in with email and password", message: "Use the email and password you sign in to App Store Connect with.")
            }
        }
    }
}
