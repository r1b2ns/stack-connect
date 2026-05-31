import SwiftUI

struct ReleaseNotesView: View {

    let releaseNotes: ReleaseNotes
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            buildTitle()

            Spacer()
                .frame(height: 40)

            buildHighlights()

            Spacer()

            buildContinueButton()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Title

    private func buildTitle() -> some View {
        VStack(spacing: 8) {
            Text(releaseNotes.title ?? String(localized: "What's New"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(String(localized: "Version \(releaseNotes.version)"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Highlights

    private func buildHighlights() -> some View {
        VStack(spacing: 28) {
            ForEach(releaseNotes.highlights) { highlight in
                buildHighlightRow(
                    icon: highlight.icon,
                    iconColor: highlight.iconColor,
                    title: highlight.title,
                    description: highlight.description
                )
            }
        }
    }

    private func buildHighlightRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(iconColor)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Continue button

    private func buildContinueButton() -> some View {
        Button(action: onContinue) {
            Text("Continue")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

#Preview {
    ReleaseNotesView(
        releaseNotes: ReleaseNotes(
            version: "1.2.0",
            title: "What's New",
            highlights: [
                .init(
                    icon: "sparkles",
                    color: "blue",
                    title: "Release Notes",
                    description: "See what changed every time you update the app."
                ),
                .init(
                    icon: "bolt.fill",
                    color: "orange",
                    title: "Faster Sync",
                    description: "Your accounts now refresh quicker than ever."
                ),
                .init(
                    icon: "lock.shield.fill",
                    color: "green",
                    title: "Improved Security",
                    description: "Credentials are stored more safely in the Keychain."
                )
            ]
        ),
        onContinue: {}
    )
}
