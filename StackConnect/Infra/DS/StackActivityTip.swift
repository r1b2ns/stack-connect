import SwiftUI

/// Design System tip for something the app is doing on its own right now:
/// `{icon} {text} ——— [spinner]` on a rounded background tinted with `tint`.
///
/// Stays on screen for as long as the caller shows it (unlike a toast), and
/// reads apart from the plain "Syncing…" line (`HomeSyncBanner`): its own
/// icon, the tinted background and the tinted spinner. Used by the Home tip
/// "Reconnecting Apple ID …" (`HomeReconnectingTip`).
struct StackActivityTip: View {

    let systemImage: String
    var tint: Color = .blue
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            ProgressView()
                .controlSize(.small)
                .tint(tint)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .listRowSeparator(.hidden)
    }
}

#Preview {
    List {
        StackActivityTip(systemImage: "person.badge.key.fill", text: "Reconnecting Apple ID dev@example.com…")
        StackActivityTip(systemImage: "person.badge.key.fill", tint: .indigo, text: "Reconnecting 2 Apple IDs…")
    }
}
