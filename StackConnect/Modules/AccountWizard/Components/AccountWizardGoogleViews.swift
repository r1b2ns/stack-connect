import SwiftUI

// MARK: - Trust facts

/// What happens on Google's page, before it opens.
enum AccountWizardGoogleTrust {
    static var items: [StackTrustItem] {
        [
            StackTrustItem(systemImage: "lock.rectangle.on.rectangle",
                           text: String(localized: "Google's page opens in a secure system window.",
                                        comment: "Account wizard, Google sign-in: trust fact.")),
            StackTrustItem(systemImage: "eye.slash",
                           text: String(localized: "StackConnect never sees your Google password.",
                                        comment: "Account wizard, Google sign-in: trust fact.")),
            StackTrustItem(systemImage: "key.fill",
                           text: String(localized: "You approve the access, and the sign-in stays in this device's Keychain.",
                                        comment: "Account wizard, Google sign-in: trust fact."))
        ]
    }
}

// MARK: - Web sign-in (Credentials)

/// The `.webSignIn` Credentials component: "Sign in with Google" through
/// `ASWebAuthenticationSession`, by the existing `AddAccountViewModel`. The
/// bottom button opens Google's page; once the apps or projects are listed,
/// the wizard moves on to Items by itself.
struct AccountWizardGoogleSignInView<ViewModel: AddAccountViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    private var google: GoogleSignInState { viewModel.uiState.google }

    var body: some View {
        if let login = google.login {
            Section {
                LabeledContent(String(localized: "Signed in as"), value: login.displayName)

                Button(String(localized: "Use Another Google Account")) {
                    Task { await viewModel.signInWithGoogle() }
                }
                .disabled(viewModel.uiState.isBusy)
            } header: {
                Text("Google Account")
            }
        } else {
            Section {
                StackTrustCard(items: AccountWizardGoogleTrust.items, tint: viewModel.uiState.providerType.color, style: .tinted)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text(viewModel.uiState.providerType == .googlePlay
                     ? String(localized: "Sign in with the Google account you use in Play Console, then pick the apps to add. StackConnect only gets the access you allow, and your sign-in stays on this device.")
                     : String(localized: "Sign in with the Google account you use in the Firebase console, then pick the projects to add. StackConnect only gets the access you allow, and your sign-in stays on this device."))
            }
        }

        if google.step == .signingIn || google.step == .loading {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(google.step == .signingIn
                         ? String(localized: "Waiting for Google…", comment: "Account wizard: Google's sign-in page is open.")
                         : viewModel.uiState.providerType == .googlePlay
                            ? String(localized: "Looking for your Google Play apps…")
                            : String(localized: "Looking for your Firebase projects…"))
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let notice = google.notice {
            Section {
                StackNoticeRow(text: notice, style: .success)
            }
        }

        if let error = google.errorMessage {
            AccountWizardErrorSection(message: error)
        }

        if !google.disabledFeatures.isEmpty {
            AccountWizardGoogleMissingAccessSection(viewModel: viewModel)
        }
    }
}

// MARK: - Missing access

/// The features left off by unticked checkboxes on Google's consent page,
/// and the way to grant them.
struct AccountWizardGoogleMissingAccessSection<ViewModel: AddAccountViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        Section {
            ForEach(viewModel.uiState.google.disabledFeatures, id: \.self) { feature in
                Label(feature.displayName, systemImage: "xmark.circle")
                    .foregroundStyle(.orange)
            }

            Button(String(localized: "Grant Access")) {
                Task { await viewModel.grantMissingGoogleAccess() }
            }
            .disabled(viewModel.uiState.isBusy)
        } header: {
            Text("Access Not Granted")
        } footer: {
            Text("These stay off because their checkbox was unticked on Google's consent page. Tap Grant Access to allow them.")
        }
    }
}

// MARK: - Picker (Items)

/// The apps (Google Play) or projects (Firebase) the Google login can add.
struct AccountWizardGooglePickerView<ViewModel: AddAccountViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    private var google: GoogleSignInState { viewModel.uiState.google }
    private var isPlay: Bool { viewModel.uiState.providerType == .googlePlay }

    var body: some View {
        Section {
            ForEach(google.items) { item in
                StackTrackedButton(.toggleApp, on: .accountWizardItems) {
                    viewModel.toggleGoogleItem(item.id)
                } label: {
                    StackSelectableRow(
                        title: item.resource.title,
                        subtitle: item.resource.subtitle,
                        isSelected: google.selectedIds.contains(item.id),
                        note: item.isAlreadyAdded ? String(localized: "Already added") : nil
                    )
                }
                .disabled(item.isAlreadyAdded)
            }
        } header: {
            HStack {
                Text(isPlay ? String(localized: "Apps") : String(localized: "Projects"))
                Spacer()
                if google.selectableItems.count > 1 {
                    Button(google.areAllSelected ? String(localized: "Select None") : String(localized: "Select All")) {
                        viewModel.setAllGoogleItemsSelected(!google.areAllSelected)
                    }
                    .font(.footnote)
                    .textCase(nil)
                }
            }
        } footer: {
            Text(isPlay
                 ? String(localized: "One account is added for this Google login. With every app selected, apps you get access to later show up too.")
                 : String(localized: "Each project is added as its own account."))
        }

        if let error = google.errorMessage {
            AccountWizardErrorSection(message: error)
        }

        if !google.disabledFeatures.isEmpty {
            AccountWizardGoogleMissingAccessSection(viewModel: viewModel)
        }
    }
}

// MARK: - Reconnect

/// Reconnecting a Google account: the same Google user signs in again on
/// Google's page (`GoogleAccessRecovery`), started by the bottom button.
struct AccountWizardGoogleReconnectView: View {

    let account: AccountModel

    var body: some View {
        Section {
            StackTrustCard(items: AccountWizardGoogleTrust.items, tint: account.providerType.color, style: .tinted)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        Section {
            StackAccountRow(account: account, showsChevron: false)
        } header: {
            Text("Account", comment: "Account wizard: the account being reconnected.")
        }
    }
}
