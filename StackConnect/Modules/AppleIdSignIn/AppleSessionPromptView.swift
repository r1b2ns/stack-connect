import SwiftUI

// MARK: - Screen modifier

extension View {
    /// Presents the "sign in again" prompt over the app when an Apple ID
    /// session expires (plan `apple-id-sign-in.md` D5), and the sign-in for
    /// that Apple ID from it. Attach once, at the root.
    func appleSessionExpiryPrompt() -> some View {
        modifier(AppleSessionExpiryPromptModifier())
    }
}

private struct AppleSessionExpiryPromptModifier: ViewModifier {

    @StateObject private var viewModel = AppleSessionPromptViewModel()

    func body(content: Content) -> some View {
        content
            // A swipe down counts as "Not Now": no new prompt this launch.
            .sheet(item: Binding(
                get: { viewModel.uiState.prompt },
                set: { if $0 == nil, viewModel.uiState.prompt != nil { viewModel.notNow() } }
            )) { prompt in
                AppleSessionPromptView(viewModel: viewModel, prompt: prompt)
            }
    }
}

// MARK: - View

/// The expired-session sheet: `StackSignInAgainPromptView`, then the Apple ID
/// sign-in in `.signInAgain` mode (the same screens as Add Account, with the
/// Apple ID fixed). A finished sign-in replaces the session for every team
/// account of that Apple ID.
struct AppleSessionPromptView<ViewModel: AppleSessionPromptViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let prompt: AppleSessionPrompt

    var body: some View {
        NavigationStack {
            buildPrompt()
                .navigationDestination(isPresented: $viewModel.uiState.isSigningIn) {
                    AppleIdSignInViewFactory.build(mode: .signInAgain(appleId: prompt.appleId)) {
                        viewModel.signInFinished()
                    }
                }
        }
        .trackScreen(.appleSessionExpired)
        .interactiveDismissDisabled(viewModel.uiState.isSigningIn)
    }

    private func buildPrompt() -> some View {
        StackSignInAgainPromptView(
            title: String(localized: "Sign In to Apple Again"),
            message: String(localized: "Your Apple ID session for App Store Connect expired. Sign in again with the same Apple ID to keep using its accounts. Until then they don't refresh in the background."),
            caption: prompt.appleId,
            onPrimary: { viewModel.signInAgain() },
            secondaryTitle: String(localized: "Not Now"),
            secondaryButton: .notNow,
            onSecondary: { viewModel.notNow() }
        )
    }
}
