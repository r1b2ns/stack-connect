import SwiftUI

struct ProviderCardView: View {

    let provider: ProviderType

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: provider.iconName)
                .font(.system(size: 40))
                .foregroundStyle(provider.color)

            Text(provider.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(provider.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(provider.color.opacity(0.2), lineWidth: 1)
        )
    }
}
