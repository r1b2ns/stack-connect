import SwiftUI

// MARK: - Display

extension AccountStatus.Level {
    /// Chip text, next to the role chip ("Admin", "App Manager").
    var title: String {
        switch self {
        case .disconnected:
            return String(localized: "Disconnected", comment: "Chip on an account (or its apps) whose login expired or whose credentials can't be used.")
        case .reconnecting:
            return String(localized: "Reconnecting…", comment: "Chip on an account (or its apps) whose expired Apple ID sign-in the app is renewing on its own with the saved password.")
        case .needsAttention:
            return String(localized: "Action Needed", comment: "Chip on an account (or its apps) with something pending, e.g. App Store Connect agreements to accept.")
        }
    }

    var color: Color {
        switch self {
        case .disconnected:   return .red
        case .reconnecting:   return .blue
        case .needsAttention: return .orange
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected:   return "bolt.horizontal.circle.fill"
        case .reconnecting:   return "arrow.triangle.2.circlepath"
        case .needsAttention: return "exclamationmark.triangle.fill"
        }
    }
}

extension AccountStatusIssue {
    /// One sentence saying what is wrong and what to do.
    var message: String {
        switch self {
        case .signInExpired:
            return String(localized: "The sign-in of this account expired. Sign in again from the Home screen to sync it.", comment: "Account status notice: the Apple ID session or Google login expired.")
        case .signInReconnecting:
            return String(localized: "The sign-in of this account expired. Signing in again with the saved password…", comment: "Account status notice: the app is renewing the expired Apple ID session on its own.")
        case .accessExpired:
            return String(localized: "This shared account expired. Re-import its file to keep using it.", comment: "Account status notice: an imported account file expired.")
        case .missingCredentials:
            return String(localized: "The credentials of this account are missing on this device. Remove the account and add it again.", comment: "Account status notice: no Keychain credentials for the account.")
        case .pendingAgreements:
            return String(localized: "App Store Connect has agreements waiting to be accepted by the Account Holder. Some data may not sync until then.", comment: "Account status notice: pending App Store Connect agreements.")
        case .accessExpiringSoon:
            return String(localized: "This shared account expires within 24 hours. Ask for a new file to keep using it.", comment: "Account status notice: an imported account file expires soon.")
        }
    }
}

extension AccountStatus {
    /// VoiceOver label of the chip: the level, then what is wrong.
    var accessibilityLabel: String {
        let details = issues.map(\.message).joined(separator: " ")
        return String(localized: "Account status: \(level.title). \(details)", comment: "VoiceOver label of the account status chip. Arguments: the chip text (Disconnected / Action Needed), then the explanation.")
    }
}

// MARK: - Chip

/// "Disconnected" (red) or "Action Needed" (orange) chip, in the style of the
/// role chip (`StackCapsuleBadge`). Shown in the accounts lists and on the
/// apps of an affected account.
struct StackAccountStatusBadge: View {

    let status: AccountStatus

    var body: some View {
        StackCapsuleBadge(title: status.level.title, color: status.level.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.accessibilityLabel)
    }
}

// MARK: - Notice

/// The top row of a single-account apps list whose account has a problem:
/// the status chip, then what is wrong and what to do.
struct StackAccountStatusNotice: View {

    let status: AccountStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: status.level.systemImage)
                .foregroundStyle(status.level.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                StackCapsuleBadge(title: status.level.title, color: status.level.color)
                ForEach(status.issues, id: \.self) { issue in
                    Text(issue.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
    }
}

// MARK: - List section / inset

/// The notice as the first `List` section of an apps list; nothing when the
/// account has no status.
struct StackAccountStatusSection: View {

    let status: AccountStatus?

    var body: some View {
        if let status {
            Section {
                StackAccountStatusNotice(status: status)
            }
        }
    }
}

extension View {
    /// Pins the notice above a non-list state (empty list, error) of an apps
    /// list, so the reason stays visible when there is nothing to scroll.
    func stackAccountStatusInset(_ status: AccountStatus?) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if let status {
                StackAccountStatusNotice(status: status)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
    }
}

#Preview {
    List {
        if let disconnected = AccountStatus(issues: [.signInExpired]) {
            StackAccountStatusBadge(status: disconnected)
            StackAccountStatusNotice(status: disconnected)
        }
        if let attention = AccountStatus(issues: [.pendingAgreements]) {
            StackAccountStatusBadge(status: attention)
            StackAccountStatusNotice(status: attention)
        }
    }
}
