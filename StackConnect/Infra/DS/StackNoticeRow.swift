import SwiftUI

/// A short line of information in a Form row: `{icon} {text}` in a tint.
///
/// For facts the user should read before or after an action, such as "the
/// password is used once and not saved", "a code was sent to …" or a success
/// note. Errors use `StackInlineErrorSection` instead. Used by the Apple ID
/// sign-in screens (`AppleIdSignInView`).
struct StackNoticeRow: View {

    enum Style {
        case info
        case success
        case privacy

        var systemImage: String {
            switch self {
            case .info:    return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .privacy: return "lock.shield.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info:    return .secondary
            case .success: return .green
            case .privacy: return .blue
            }
        }
    }

    let text: String
    var style: Style = .info

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(style == .info ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: style.systemImage)
                .foregroundStyle(style.tint)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
    }
}

#Preview {
    Form {
        StackNoticeRow(text: "Your password is saved only in this device's Keychain.", style: .privacy)
        StackNoticeRow(text: "Enter the code shown on your Apple devices.")
        StackNoticeRow(text: "Signed in.", style: .success)
    }
}
