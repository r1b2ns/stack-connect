import SwiftUI

/// Reusable Design System list row with the layout
/// `{icon} {title} ——— [badge] [New chip] {chevron}` used across
/// navigational lists (e.g. `AppDetailView`'s General / App Store /
/// TestFlight sections). Optionally shows an accent-colored "New" chip
/// just before the chevron via `showsNewChip`.
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
    var showsNewChip: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.body)

            Spacer()

            if case .exclamation = badge {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.body)
            }

            if showsNewChip {
                Text(String(localized: "New"))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
