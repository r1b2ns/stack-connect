import SwiftUI

// MARK: - PermissionType

enum PermissionType {

    case pushNotifications
    case faceID

    var icon: String {
        switch self {
        case .pushNotifications: return "bell.badge.fill"
        case .faceID:            return "faceid"
        }
    }

    var iconColor: Color {
        switch self {
        case .pushNotifications: return .orange
        case .faceID:            return .blue
        }
    }

    var title: String {
        switch self {
        case .pushNotifications: return String(localized: "Stay in the Loop")
        case .faceID:            return String(localized: "Secure with Face ID")
        }
    }

    var allowButtonTitle: String {
        switch self {
        case .pushNotifications: return String(localized: "Allow Notifications")
        case .faceID:            return String(localized: "Enable Face ID")
        }
    }

    fileprivate var features: [PermissionFeature] {
        switch self {
        case .pushNotifications:
            return [
                .init(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: String(localized: "Account Updates"),
                    description: String(localized: "Know instantly when something changes in your connected accounts.")
                ),
                .init(
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    title: String(localized: "Security Alerts"),
                    description: String(localized: "Get notified about important security events.")
                ),
                .init(
                    icon: "bell.slash.fill",
                    iconColor: .gray,
                    title: String(localized: "No Spam"),
                    description: String(localized: "Only essential alerts — no marketing or irrelevant notifications.")
                )
            ]
        case .faceID:
            return [
                .init(
                    icon: "faceid",
                    iconColor: .blue,
                    title: String(localized: "Quick Access"),
                    description: String(localized: "Unlock the app instantly with a glance.")
                ),
                .init(
                    icon: "lock.fill",
                    iconColor: .green,
                    title: String(localized: "Secure"),
                    description: String(localized: "Your biometric data never leaves your device.")
                ),
                .init(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .orange,
                    title: String(localized: "Fallback"),
                    description: String(localized: "Always falls back to your passcode if needed.")
                )
            ]
        }
    }
}

// MARK: - PermissionFeature

private struct PermissionFeature {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
}

// MARK: - PermissionRequestView

struct PermissionRequestView: View {

    let permissionType: PermissionType
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            buildIcon()

            Spacer()
                .frame(height: 24)

            buildTitle()

            Spacer()
                .frame(height: 40)

            buildFeatures()

            Spacer()

            buildAllowButton()

            Spacer()
                .frame(height: 20)

            buildSkipButton()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .interactiveDismissDisabled(true)
    }

    // MARK: - Icon

    private func buildIcon() -> some View {
        Image(systemName: permissionType.icon)
            .font(.system(size: 64))
            .foregroundStyle(permissionType.iconColor)
            .padding(24)
            .background(
                permissionType.iconColor.opacity(0.12),
                in: Circle()
            )
    }

    // MARK: - Title

    private func buildTitle() -> some View {
        Text(permissionType.title)
            .font(.largeTitle)
            .fontWeight(.bold)
            .multilineTextAlignment(.center)
    }

    // MARK: - Features

    private func buildFeatures() -> some View {
        VStack(spacing: 28) {
            ForEach(permissionType.features.indices, id: \.self) { index in
                buildFeatureRow(permissionType.features[index])
            }
        }
    }

    private func buildFeatureRow(_ feature: PermissionFeature) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.title)
                .foregroundStyle(feature.iconColor)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Buttons

    private func buildAllowButton() -> some View {
        Button(action: onAllow) {
            Text(permissionType.allowButtonTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func buildSkipButton() -> some View {
        Button(action: onSkip) {
            Text("Not Now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }
}
