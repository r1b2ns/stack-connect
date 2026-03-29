import SwiftUI

struct ToastView: View {

    let message: String
    let icon: String

    init(message: String, icon: String = "arrow.triangle.2.circlepath") {
        self.message = message
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {

    @Binding var isPresented: Bool
    let message: String
    let icon: String
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isPresented {
                ToastView(message: message, icon: icon)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation { isPresented = false }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.3), value: isPresented)
    }
}

extension View {
    func toast(
        isPresented: Binding<Bool>,
        message: String,
        icon: String = "arrow.triangle.2.circlepath",
        duration: TimeInterval = 3
    ) -> some View {
        modifier(
            ToastModifier(
                isPresented: isPresented,
                message: message,
                icon: icon,
                duration: duration
            )
        )
    }
}
