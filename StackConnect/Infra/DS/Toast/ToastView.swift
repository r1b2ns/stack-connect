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
        content.overlay(alignment: .bottom) {
            if isPresented {
                ToastView(message: message, icon: icon)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

    func toast(
        message: Binding<ToastMessage?>,
        duration: TimeInterval = 3
    ) -> some View {
        modifier(
            DynamicToastModifier(
                message: message,
                duration: duration
            )
        )
    }
}

// MARK: - Dynamic Toast

struct ToastMessage: Equatable {
    let text: String
    let icon: String

    init(_ text: String, icon: String = "checkmark.circle.fill") {
        self.text = text
        self.icon = icon
    }
}

struct DynamicToastModifier: ViewModifier {

    @Binding var message: ToastMessage?
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = message {
                ToastView(message: toast.text, icon: toast.icon)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation { message = nil }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.3), value: message)
    }
}
