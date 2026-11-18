import SwiftUI

/// A titled card for the wide (regular-width) layouts that lay detail screens
/// out as a grid instead of one long list. Same surface as the Home widgets.
struct StackCard<Content: View, Accessory: View>: View {

    let title: String
    var systemImage: String?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        systemImage: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                } else {
                    Text(title)
                        .font(.headline)
                }
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

/// A tappable row inside a `StackCard`: plain button with a hover highlight,
/// so it works with touch, pointer and keyboard.
struct StackCardButton<Label: View>: View {

    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .contentShape(Rectangle())
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}
