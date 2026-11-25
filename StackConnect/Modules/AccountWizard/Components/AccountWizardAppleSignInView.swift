import SwiftUI

/// The `.credentials(twoFactor: true)` Credentials component's lifecycle:
/// the existing email and password sign-in of App Store Connect
/// (`AppleIdSignInViewModel`, rendered by `AppleIdSignInSections`). Applied
/// to the step's `Form`, so it runs once whatever the number of sections.
/// "Save password on this device" is off by default and nothing here looks
/// like "Sign in with Apple" (no Apple logo, neutral wording).
struct AccountWizardAppleSignInLifecycle<ViewModel: AppleIdSignInViewModelProtocol>: ViewModifier {

    @ObservedObject var viewModel: ViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.uiState.email) { _, _ in viewModel.emailDidChange() }
            // Signing in again with a saved password needs only the code.
            .task { await viewModel.signInWithSavedPasswordIfAvailable() }
            // Flag `accountConnectionGuide`: opened from the trust panel.
            .sheet(isPresented: $viewModel.uiState.isShowingPasswordUsage) {
                ApplePasswordUsageView {
                    viewModel.uiState.isShowingPasswordUsage = false
                }
            }
    }
}

/// Review of an email and password sign-in: the teams picked, their role
/// read from App Store Connect, and what stays on the device.
struct AccountWizardAppleReview<ViewModel: AppleIdSignInViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let kind: AccountWizardKindConfig

    private var teams: [String] {
        viewModel.uiState.selectableTeams
            .filter { viewModel.uiState.selectedTeamIds.contains($0.id) }
            .map(\.team.name)
    }

    var body: some View {
        AccountWizardSummarySection(rows: [
            .init(title: String(localized: "Type", comment: "Account wizard review: the account type."), value: AccountWizardCopy.title(of: kind.kind)),
            .init(title: String(localized: "Connection", comment: "Account wizard review: how the account connects."), value: AccountWizardCopy.label(of: .appleIdSignIn)),
            .init(title: String(localized: "Teams", comment: "Account wizard: short name of the team selection step."),
                  value: teams.isEmpty ? String(localized: "Renew the sign-in", comment: "Account wizard review: every team was already added; saving renews their session.") : teams.formatted(.list(type: .and))),
            .init(title: String(localized: "Role"), value: String(localized: "Read from App Store Connect", comment: "Account wizard review: the role of an email and password account comes from the team.")),
            .init(title: String(localized: "Stored", comment: "Account wizard review: where the credentials are kept."),
                  value: AccountWizardCopy.storage(of: .appleIdSignIn, savesPassword: viewModel.uiState.savesPassword))
        ])

        if let error = viewModel.uiState.errorMessage {
            AccountWizardErrorSection(message: error)
        }
    }
}
