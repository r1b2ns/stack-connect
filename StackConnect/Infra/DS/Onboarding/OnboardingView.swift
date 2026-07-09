import SwiftUI

/// Presentational, content-driven onboarding screen.
///
/// Layout mirrors ``WelcomeView`` / ``ReleaseNotesView`` (a centered title, a
/// stack of feature rows, and a full-width continue button) but renders whatever
/// ``OnboardingContent`` it is given, so it can introduce any feature.
struct OnboardingView: View {

    let content: OnboardingContent
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            buildTitle()

            Spacer()
                .frame(height: 40)

            buildFeatures()

            Spacer()

            buildContinueButton()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Title

    private func buildTitle() -> some View {
        VStack(spacing: 8) {
            Text(content.title)
                .font(.largeTitle)
                .fontWeight(.bold)

            if let highlightedTitle = content.highlightedTitle {
                Text(highlightedTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Features

    private func buildFeatures() -> some View {
        VStack(spacing: 28) {
            ForEach(content.features) { feature in
                buildFeatureRow(
                    icon: feature.icon,
                    iconColor: feature.color,
                    title: feature.title,
                    description: feature.description
                )
            }
        }
    }

    private func buildFeatureRow(
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
            Text(content.continueTitle)
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
    OnboardingView(
        content: OnboardingCatalog.content(for: .submissions),
        onContinue: {}
    )
}
