import SwiftUI

/// Shows how many review submissions are counting against Apple's concurrency
/// limit (max 5). Turns into a danger banner once the limit is reached, nudging
/// the user to discard a draft before starting a new review.
struct SubmissionsLimitBanner: View {

    let concurrentCount: Int
    let concurrentLimit: Int
    let limitReached: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "\(concurrentCount) of \(concurrentLimit) submissions in progress"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(limitReached ? accentColor : .primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .listRowBackground(limitReached ? accentColor.opacity(0.1) : nil)
    }

    // MARK: - Styling

    private var iconName: String {
        limitReached ? "exclamationmark.triangle.fill" : "info.circle.fill"
    }

    private var accentColor: Color {
        limitReached ? .red : .secondary
    }

    private var subtitle: String {
        if limitReached {
            return String(localized: "You've hit Apple's limit. Discard a draft to submit a new version.")
        }
        return String(localized: "Apple allows up to \(concurrentLimit) review submissions in progress at once.")
    }
}
