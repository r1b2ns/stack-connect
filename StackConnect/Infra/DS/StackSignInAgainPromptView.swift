import SwiftUI

/// Provider-neutral "sign in again" state: an account's login expired or was
/// revoked and only the user can renew it. A `StackPermissionRequestView`
/// with the orange "person with a warning" glyph, the provider's title and
/// message, the feedback of the last attempt and "Sign In Again" / a
/// secondary button.
///
/// Used by the Google screens (`StackGoogleAccessPromptView`, `.signInRequired`)
/// and by the expired Apple ID session prompt (`AppleSessionPromptView`).
/// Tracking of the primary action belongs to the caller.
struct StackSignInAgainPromptView: View {

    let title: String
    let message: String
    /// Why the last attempt didn't work, if any.
    var feedback: String?
    /// The login the prompt is about (e.g. an e-mail), shown under the message.
    var caption: String?
    var isWorking = false
    let onPrimary: () -> Void
    var secondaryTitle: String = String(localized: "Go Back")
    var secondaryButton: AnalyticsButton = .back
    var onSecondary: (() -> Void)?

    var body: some View {
        StackPermissionRequestView(
            systemImage: "person.crop.circle.badge.exclamationmark",
            tint: .orange,
            title: title,
            message: message,
            feedback: feedback,
            caption: caption,
            primaryTitle: String(localized: "Sign In Again"),
            isWorking: isWorking,
            onPrimary: onPrimary,
            secondaryTitle: onSecondary == nil ? nil : secondaryTitle,
            secondaryButton: secondaryButton,
            onSecondary: onSecondary
        )
    }
}

#Preview {
    StackSignInAgainPromptView(
        title: "Sign In to Apple Again",
        message: "Your Apple ID session expired.",
        caption: "dev@example.com",
        onPrimary: {},
        secondaryTitle: "Not Now",
        onSecondary: {}
    )
}
