import SwiftUI

/// A KPI tile: a big number over a short caption, with a tinted glyph. Used by
/// the regular-width Dashboard's summary strip. Tappable when `action` is set
/// (pointer-friendly: a plain button, so it gets hover and keyboard focus).
struct StackMetricTile: View {

    let value: String
    let title: String
    let systemImage: String
    let tint: Color
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                buildContent()
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        } else {
            buildContent()
        }
    }

    private func buildContent() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
