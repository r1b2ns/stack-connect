import SwiftUI

// MARK: - Flow layout

/// Lays its subviews out left to right, wrapping to a new line when the next
/// one doesn't fit (chips, tags).
struct StackFlowLayout: Layout {

    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let usedWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? usedWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private struct Row {
        var items: [(index: Int, x: CGFloat, size: CGSize)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let x = current.items.isEmpty ? 0 : current.width + spacing
            if !current.items.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + lineSpacing)
            }
            let placedX = current.items.isEmpty ? 0 : current.width + spacing
            current.items.append((index, placedX, size))
            current.width = placedX + size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

// MARK: - Outlined chips

/// Single-choice filter chips that wrap onto several lines: outlined capsules
/// on the card surface, the selected one filled with the accent color. For a
/// single scrolling line use `StackFilterChips`.
struct StackFlowFilterChips<Item: Hashable>: View {

    let items: [Item]
    let selection: Item
    let title: (Item) -> String
    var height: CGFloat = 32
    let onSelect: (Item) -> Void

    var body: some View {
        StackFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { onSelect(item) }
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minHeight: height)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(
                            Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            Capsule().stroke(isSelected ? Color.accentColor : Color(.systemGray4), lineWidth: 1)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

#Preview {
    StackFlowFilterChips(
        items: ["All", "Apple", "Google", "Telemetry", "On Device", "Errors"],
        selection: "All",
        title: { $0 },
        onSelect: { _ in }
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
