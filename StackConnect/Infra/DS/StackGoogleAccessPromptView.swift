import SwiftUI

/// A Firebase screen's `GoogleAccessPrompt` as a `StackPermissionRequestView`:
/// "Grant access" for a missing sensitive permission (Remote Config,
/// Analytics), or "Sign in again" for an expired or revoked Google login
/// (the provider-neutral `StackSignInAgainPromptView`).
///
/// `onPrimary` runs the ViewModel's resolution (`GoogleAccessRecovery`),
/// which tracks it; `onSecondary` is the path back (tracked as `back`).
struct StackGoogleAccessPromptView: View {

    let prompt: GoogleAccessPrompt
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        switch prompt.reason {
        case .permissionNeeded(let feature):
            StackPermissionRequestView(
                systemImage: feature.systemImage,
                title: feature.title,
                message: feature.explanation,
                notice: GoogleSensitiveScopeFeature.unverifiedAppNotice,
                feedback: prompt.feedback,
                caption: prompt.email,
                primaryTitle: String(localized: "Grant Access"),
                isWorking: prompt.isWorking,
                onPrimary: onPrimary,
                secondaryTitle: String(localized: "Go Back"),
                onSecondary: onSecondary
            )
        case .signInRequired:
            StackSignInAgainPromptView(
                title: String(localized: "Sign In to Google Again"),
                message: signInMessage,
                feedback: prompt.feedback,
                isWorking: prompt.isWorking,
                onPrimary: onPrimary,
                onSecondary: onSecondary
            )
        }
    }

    private var signInMessage: String {
        if let email = prompt.email {
            return String(localized: "The Google sign-in for \(email) expired or was revoked. Sign in again with the same Google account to keep using this account.",
                          comment: "Firebase screen of an account added with Sign in with Google, when its Google sign-in expired. The placeholder is the Google account's e-mail.")
        }
        return String(localized: "Your Google sign-in expired or was revoked. Sign in again with the same Google account to keep using this account.")
    }
}

// MARK: - Screen modifier

extension View {
    /// Replaces the screen's content with `prompt` while it is set (a Firebase
    /// screen of a Google sign-in account). The primary button runs `resolve`
    /// (the ViewModel's `resolveGoogleAccess()`); the secondary one goes back.
    func googleAccessPrompt(_ prompt: GoogleAccessPrompt?, resolve: @escaping () async -> Void) -> some View {
        modifier(GoogleAccessPromptModifier(prompt: prompt, resolve: resolve))
    }
}

private struct GoogleAccessPromptModifier: ViewModifier {

    let prompt: GoogleAccessPrompt?
    let resolve: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @ViewBuilder
    func body(content: Content) -> some View {
        if let prompt {
            StackGoogleAccessPromptView(
                prompt: prompt,
                onPrimary: { Task { await resolve() } },
                onSecondary: { dismiss() }
            )
        } else {
            content
        }
    }
}

#Preview("Permission") {
    StackGoogleAccessPromptView(
        prompt: GoogleAccessPrompt(reason: .permissionNeeded(.analytics), email: "dev@example.com"),
        onPrimary: {},
        onSecondary: {}
    )
}

#Preview("Sign in again") {
    StackGoogleAccessPromptView(
        prompt: GoogleAccessPrompt(reason: .signInRequired, email: "dev@example.com", feedback: "You signed in with a different Google account."),
        onPrimary: {},
        onSecondary: {}
    )
}
