import SwiftUI

/// Design System row for a priced, one-tap purchase:
/// `{emoji} {title / subtitle} ——— [price button]`.
///
/// While `isPurchasing` the price is replaced by a spinner; `isDisabled` greys
/// the button out (e.g. while another row is purchasing). Only the price
/// button is tappable; the purchase logic belongs to the caller.
struct StackTipRow: View {

    let emoji: String
    let title: String
    let subtitle: String
    let price: String
    var isPurchasing: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.largeTitle)
                .frame(width: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            buildPriceButton()
        }
        .padding(.vertical, 4)
    }

    private func buildPriceButton() -> some View {
        Button(action: action) {
            ZStack {
                // Keeps the button's width while the spinner shows.
                Text(price)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .opacity(isPurchasing ? 0 : 1)

                if isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .disabled(isDisabled || isPurchasing)
        .accessibilityLabel(Text(verbatim: "\(title), \(price)"))
    }
}

#Preview {
    List {
        StackTipRow(emoji: "☕", title: "Coffee", subtitle: "Buy the developer a coffee.", price: "$0.99") {}
        StackTipRow(emoji: "🥪", title: "Snack", subtitle: "Buy the developer a snack.", price: "$4.99", isPurchasing: true) {}
        StackTipRow(emoji: "🍝", title: "Lunch", subtitle: "Buy the developer lunch.", price: "$9.99", isDisabled: true) {}
    }
}
