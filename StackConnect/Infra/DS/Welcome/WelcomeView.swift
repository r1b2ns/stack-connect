import SwiftUI

struct WelcomeView: View {

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
            Text("Welcome to")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("StackConnect")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Features

    private func buildFeatures() -> some View {
        VStack(spacing: 28) {
            buildFeatureRow(
                icon: "square.stack.3d.up.fill",
                iconColor: .blue,
                title: String(localized: "Multi-Service Management"),
                description: String(localized: "Connect and manage your App Store Connect and Firebase accounts in one place.")
            )

            buildFeatureRow(
                icon: "person.2.fill",
                iconColor: .green,
                title: String(localized: "Multiple Accounts"),
                description: String(localized: "Add as many accounts as you need for each service. Switch between them effortlessly.")
            )

            buildFeatureRow(
                icon: "internaldrive.fill",
                iconColor: .orange,
                title: String(localized: "Offline First"),
                description: String(localized: "Your data is always available, even without an internet connection.")
            )
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
