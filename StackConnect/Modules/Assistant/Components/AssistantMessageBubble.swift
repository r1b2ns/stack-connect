import SwiftUI

struct AssistantMessageBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack(spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 32)
            }

            Text(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if message.role == .assistant {
                Spacer(minLength: 32)
            }
        }
    }

    private var backgroundColor: Color {
        message.role == .user ? Color.accentColor : Color(.secondarySystemBackground)
    }

    private var foregroundColor: Color {
        message.role == .user ? Color.white : Color.primary
    }
}
