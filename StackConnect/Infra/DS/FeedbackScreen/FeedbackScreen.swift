import SwiftUI

// MARK: - FeedbackType

enum FeedbackType {
    case error
    case warning
    case success
    case info

    var tintColor: Color {
        switch self {
        case .error: return .red
        case .warning: return .yellow
        case .success: return .green
        case .info: return .blue
        }
    }
}

// MARK: - FeedbackScreen

struct FeedbackScreen: View {

    let type: FeedbackType
    let image: String
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            buildCloseButton()

            Spacer()

            buildImage()

            buildTitle()
                .padding(.top, 16)

            buildMessage()
                .padding(.top, 8)

            Spacer()

            buildOkButton()
        }
        .padding(24)
    }

    // MARK: - Components

    private func buildCloseButton() -> some View {
        HStack {
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buildImage() -> some View {
        Image(systemName: image)
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
            .foregroundStyle(type.tintColor)
    }

    private func buildTitle() -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    private func buildMessage() -> some View {
        Text(message)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(5)
    }

    private func buildOkButton() -> some View {
        Button {
            onDismiss()
        } label: {
            Text(String(localized: "OK"))
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(type.tintColor)
    }
}
