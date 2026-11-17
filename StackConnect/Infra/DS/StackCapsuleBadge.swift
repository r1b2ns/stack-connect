import SwiftUI

/// Small tinted capsule label shown next to a row title — e.g. an account's
/// role, "imported" or "expired" markers in the account lists.
///
/// The text is rendered in `color` over a 15% tint of the same color.
struct StackCapsuleBadge: View {

    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}
