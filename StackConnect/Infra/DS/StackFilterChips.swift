import SwiftUI

/// A horizontally scrolling strip of capsule chips with one selected: the user
/// list filters (App Store Connect and Google Play) and the Google Play invite
/// presets. Meant as a clear, separator-less row of a `List` / `Form`.
struct StackFilterChips<Item: Hashable>: View {

    let items: [Item]
    let selection: Item
    let title: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let isSelected = item == selection
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { onSelect(item) }
                    } label: {
                        Text(title(item))
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
