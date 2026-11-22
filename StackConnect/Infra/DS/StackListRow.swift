import SwiftUI

/// Reusable Design System list row with the layout
/// `{icon} {title} ——— [badge] {chevron}` used across
/// navigational lists (e.g. `AppDetailView`'s General / App Store /
/// TestFlight sections).
/// Render it as the `label` of a `Button`/`NavigationLink`; the tap and
/// navigation logic belong to the caller.
struct StackListRow: View {

    /// Optional trailing accessory shown just before the chevron.
    enum Badge {
        case exclamation
    }

    let icon: String
    let iconColor: Color
    let title: String
    var badge: Badge? = nil

    var body: some View {
        HStack(spacing: 12) {
            StackIconTile(systemName: icon, color: iconColor)

            Text(title)
                .font(.body)

            Spacer()

            if case .exclamation = badge {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.body)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
