import SwiftUI

struct AssistantButton: View {

    let action: () -> Void

    @State private var isAnimating = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 52))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(20)
        .accessibilityLabel(String(localized: "Siri Assistant"))
        .accessibilityHint(String(localized: "Opens voice assistant actions"))
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
