import SwiftUI
import UniformTypeIdentifiers

// MARK: - Factory

@MainActor
struct AddAccountViewFactory {
    static func build(providerType: ProviderType, onDismiss: @escaping () -> Void) -> some View {
        AddAccountEntry(providerType: providerType, onDismiss: onDismiss)
    }
}

// MARK: - Entry

private struct AddAccountEntry: View {
    let providerType: ProviderType
    let onDismiss: () -> Void

    @StateObject private var viewModel: AddAccountViewModel

    init(providerType: ProviderType, onDismiss: @escaping () -> Void) {
        self.providerType = providerType
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: AddAccountViewModel(providerType: providerType))
    }

    var body: some View {
        AddAccountView(viewModel: viewModel, onDismiss: onDismiss)
    }
}

// MARK: - View

struct AddAccountView<ViewModel: AddAccountViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var p8AllowedTypes: [UTType] {
        var types: [UTType] = []
        if let p8 = UTType(filenameExtension: "p8") { types.append(p8) }
        types.append(contentsOf: [.data, .item])
        return types
    }

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.uiState.isGoogleSignInMode {
                    buildGoogleSignInContent()
                } else {
                    buildKeyFileContent()
                }

                if let error = viewModel.uiState.validationError {
                    buildErrorSection(error)
                }
            }
            .navigationTitle(String(localized: "Add Account"))
            .trackScreen(.addAccount)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .disabled(viewModel.uiState.isBusy)
            .onChange(of: viewModel.uiState.isSaved) { _, isSaved in
                if isSaved {
                    onDismiss()
                }
            }
            .navigationDestination(isPresented: $viewModel.uiState.isShowingAppleIdSignIn) {
                // The accounts are saved by the sign-in itself: close Add Account.
                AppleIdSignInViewFactory.build(mode: .addAccounts, onFinished: onDismiss)
            }
        }
        // Cancel, swipe down or Save: a Google login signed in here but
        // never used by an account is signed out (no-op after a save).
        .onDisappear {
            Task { await viewModel.discardUnsavedGoogleLogin() }
        }
    }

    // MARK: - Key file (service account JSON / .p8)

    @ViewBuilder
    private func buildKeyFileContent() -> some View {
        if viewModel.uiState.isGoogleSignInAvailable {
            buildUseGoogleSignInSection()
        }

        buildNameSection()

        if viewModel.uiState.providerType == .apple {
            buildAppleCredentialsSection()
            buildAppleTutorialSection()
            if viewModel.uiState.isAppleIdSignInAvailable {
                buildAppleIdSignInSection()
            }
        }

        if viewModel.uiState.providerType == .firebase {
            buildFirebaseCredentialsSection()
            buildFirebaseTutorialSection()
        }

        if viewModel.uiState.providerType == .googlePlay {
            buildGooglePlayCredentialsSection()
            buildGooglePlayDeveloperIdSection()
            buildGooglePlayTutorialSection()
        }
    }

    private func buildUseGoogleSignInSection() -> some View {
        Section {
            Button(String(localized: "Sign in with Google instead")) {
                viewModel.setCredentialMode(.googleSignIn)
            }
        } footer: {
            Text("No service account needed: sign in with the Google account you use in the console.")
        }
    }

    // MARK: - Sections

    private func buildNameSection() -> some View {
        Section {
            TextField(
                String(localized: "Account Name"),
                text: $viewModel.uiState.accountName
            )
            .textContentType(.name)

            // App Store Connect role; Google Play accounts keep the default role.
            if viewModel.uiState.providerType.supportsAccountRole {
                Picker(
                    String(localized: "Role"),
                    selection: $viewModel.uiState.role
                ) {
                    ForEach(AccountRole.allCases, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("General")
        }
    }

    private func buildAppleCredentialsSection() -> some View {
        Section {
            HStack {
                TextField(
                    String(localized: "Issuer ID"),
                    text: $viewModel.uiState.issuerID
                )
                .textContentType(.none)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                StackPasteButton(trackingScreen: .addAccount) { viewModel.uiState.issuerID = $0 }
            }

            HStack {
                TextField(
                    String(localized: "Private Key ID"),
                    text: $viewModel.uiState.privateKeyID
                )
                .textContentType(.none)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                StackPasteButton(trackingScreen: .addAccount) { viewModel.uiState.privateKeyID = $0 }
            }

            StackKeyFileInput(
                title: String(localized: "Private Key (.p8)"),
                text: $viewModel.uiState.privateKey,
                importTitle: String(localized: "Import .p8 file"),
                allowedContentTypes: p8AllowedTypes,
                editorFont: .system(.body, design: .monospaced),
                minEditorHeight: 120,
                trackingScreen: .addAccount
            )
        } header: {
            Text("App Store Connect Credentials")
        } footer: {
            Text("Paste or import the .p8 file content along with its Key ID and Issuer ID.")
        }
    }

    /// "Sign in with Apple ID" (flag `appleIdSignIn`): the alternative to the
    /// API key, without creating a key in App Store Connect.
    private func buildAppleIdSignInSection() -> some View {
        Section {
            StackSignInButton(
                title: String(localized: "Sign in with Apple ID"),
                systemImage: "apple.logo"
            ) {
                viewModel.openAppleIdSignIn()
            }
        } header: {
            Text("No API Key?")
        } footer: {
            Text("Sign in with your Apple ID and its two-factor code instead, then pick the teams to add. Your password is used once and not saved. Analytics Reports need an API key.")
        }
    }

    private func buildAppleTutorialSection() -> some View {
        TutorialGuideView(
            label: String(localized: "How to generate the API key"),
            systemImage: "questionmark.circle",
            blocks: [
                TutorialBlock(
                    icon: "questionmark.circle",
                    title: String(localized: "How to generate the API key"),
                    steps: [
                        TutorialStep(
                            text: String(localized: "Open App Store Connect"),
                            detail: String(localized: "Go to appstoreconnect.apple.com and sign in with your Apple ID.")
                        ),
                        TutorialStep(
                            text: String(localized: "Users and Access"),
                            detail: String(localized: "In the top navigation, go to Users and Access.")
                        ),
                        TutorialStep(
                            text: String(localized: "Integrations > App Store Connect API"),
                            detail: String(localized: "Select the Integrations tab, then choose App Store Connect API. Make sure Team Keys is selected.")
                        ),
                        TutorialStep(
                            text: String(localized: "Generate a new key"),
                            detail: String(localized: "Tap the + button, give the key a name, choose the desired access level, and confirm.")
                        ),
                        TutorialStep(
                            text: String(localized: "Copy the Issuer ID and Key ID"),
                            detail: String(localized: "The Issuer ID appears at the top of the page. The Key ID is listed next to your newly created key.")
                        ),
                        TutorialStep(
                            text: String(localized: "Download the .p8 file"),
                            detail: String(localized: "Tap \"Download API Key\" — this is the only time you can download it. Use \"Import .p8 file\" above to load it.")
                        )
                    ],
                    isShareable: false
                )
            ]
        )
    }

    private func buildFirebaseCredentialsSection() -> some View {
        buildServiceAccountKeySection(
            text: $viewModel.uiState.firebaseJSON,
            header: String(localized: "Firebase Credentials"),
            footer: String(localized: "Paste or import the full JSON content of your Google Service Account key file.")
        )
    }

    private func buildFirebaseTutorialSection() -> some View {
        TutorialGuideView(
            label: String(localized: "How to generate the JSON key"),
            systemImage: "questionmark.circle",
            blocks: [
                TutorialBlock(
                    icon: "questionmark.circle",
                    title: String(localized: "How to generate the JSON key"),
                    steps: [
                        TutorialStep(
                            text: String(localized: "Open Firebase Console"),
                            detail: String(localized: "Go to console.firebase.google.com and select your project.")
                        ),
                        TutorialStep(
                            text: String(localized: "Project Settings"),
                            detail: String(localized: "Tap the gear icon next to \"Project Overview\" and select Project settings.")
                        ),
                        TutorialStep(
                            text: String(localized: "Service Accounts tab"),
                            detail: String(localized: "Navigate to the \"Service accounts\" tab at the top of the page.")
                        ),
                        TutorialStep(
                            text: String(localized: "Generate new private key"),
                            detail: String(localized: "Scroll down and tap \"Generate new private key\", then confirm.")
                        ),
                        TutorialStep(
                            text: String(localized: "Import the .json file"),
                            detail: String(localized: "A .json file will be downloaded. Use \"Import .json file\" above to load it.")
                        )
                    ],
                    isShareable: false
                )
            ]
        )
    }

    private func buildGooglePlayCredentialsSection() -> some View {
        buildServiceAccountKeySection(
            text: $viewModel.uiState.googlePlayJSON,
            header: String(localized: "Google Play Credentials"),
            footer: String(localized: "Paste or import the service account's JSON key. Enable the Google Play Developer Reporting API in its Google Cloud project, then invite the service account e-mail in Play Console › Users and permissions with at least \"View app information (read-only)\". Access can take a while to propagate.")
        )
    }

    /// Optional (plan U3): only the Users tab needs it, so adding an account for
    /// releases and reviews is never blocked on it.
    private func buildGooglePlayDeveloperIdSection() -> some View {
        Section {
            LabeledContent(String(localized: "Developer ID")) {
                TextField(String(localized: "Optional"), text: $viewModel.uiState.googlePlayDeveloperId)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Developer Account")
        } footer: {
            Text("Needed only to manage users. It's the number in Play Console › Settings › Developer account (also in every Play Console URL). You can add it later in Account Settings.")
        }
    }

    private func buildGooglePlayTutorialSection() -> some View {
        TutorialGuideView(
            label: String(localized: "How to set up the service account"),
            systemImage: "questionmark.circle",
            blocks: [
                TutorialBlock(
                    icon: "questionmark.circle",
                    title: String(localized: "How to set up the service account"),
                    steps: [
                        TutorialStep(
                            text: String(localized: "Open Google Cloud Console"),
                            detail: String(localized: "Go to console.cloud.google.com and select the project that will own the service account.")
                        ),
                        TutorialStep(
                            text: String(localized: "Enable the Reporting API"),
                            detail: String(localized: "In APIs & Services › Library, search for \"Google Play Developer Reporting API\" and tap Enable.")
                        ),
                        TutorialStep(
                            text: String(localized: "Create a service account"),
                            detail: String(localized: "In IAM & Admin › Service Accounts, create a service account. It doesn't need any Google Cloud role.")
                        ),
                        TutorialStep(
                            text: String(localized: "Create a JSON key"),
                            detail: String(localized: "Open the service account, go to Keys › Add key › Create new key, choose JSON and download the file.")
                        ),
                        TutorialStep(
                            text: String(localized: "Invite it in Play Console"),
                            detail: String(localized: "In play.google.com/console, go to Users and permissions, invite the service account e-mail and grant at least \"View app information (read-only)\".")
                        ),
                        TutorialStep(
                            text: String(localized: "Import the .json file"),
                            detail: String(localized: "A .json file will be downloaded. Use \"Import .json file\" above to load it.")
                        )
                    ],
                    isShareable: false
                )
            ],
            caption: String(localized: "Play Console access can take a while (sometimes hours) to propagate. If no apps show up right away, try again later.")
        )
    }

    /// Service-account JSON key input shared by the Firebase and Google Play sections.
    private func buildServiceAccountKeySection(
        text: Binding<String>,
        header: String,
        footer: String
    ) -> some View {
        Section {
            StackKeyFileInput(
                title: String(localized: "Service Account Key (JSON)"),
                text: text,
                importTitle: String(localized: "Import .json file"),
                allowedContentTypes: [.json],
                trackingScreen: .addAccount
            )
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }

    // MARK: - Sign in with Google

    private var google: GoogleSignInState { viewModel.uiState.google }

    @ViewBuilder
    private func buildGoogleSignInContent() -> some View {
        if let login = google.login {
            buildGoogleAccountSection(login)
        } else {
            buildGoogleSignInSection()
        }

        if google.step == .loading {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(viewModel.uiState.providerType == .googlePlay
                         ? String(localized: "Looking for your Google Play apps…")
                         : String(localized: "Looking for your Firebase projects…"))
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let notice = google.notice {
            Section {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }

        if let error = google.errorMessage {
            buildErrorSection(error)
        }

        if !google.disabledFeatures.isEmpty {
            buildMissingAccessSection()
        }

        if google.step == .picking {
            if viewModel.uiState.providerType == .googlePlay {
                buildNameSection()
            }
            buildGooglePickerSection()
            if viewModel.uiState.providerType == .googlePlay {
                buildGooglePlayDeveloperIdSection()
            }
        }

        Section {
            Button(String(localized: "Use a service account JSON instead")) {
                viewModel.setCredentialMode(.keyFile)
            }
        } footer: {
            Text("For CI, shared team accounts, or if you prefer not to sign in with Google.")
        }
    }

    private func buildGoogleSignInSection() -> some View {
        Section {
            StackSignInButton(
                title: String(localized: "Sign in with Google"),
                isLoading: google.step == .signingIn
            ) {
                Task { await viewModel.signInWithGoogle() }
            }
        } footer: {
            Text(viewModel.uiState.providerType == .googlePlay
                 ? String(localized: "Sign in with the Google account you use in Play Console, then pick the apps to add. StackConnect only gets the access you allow, and your sign-in stays on this device.")
                 : String(localized: "Sign in with the Google account you use in the Firebase console, then pick the projects to add. StackConnect only gets the access you allow, and your sign-in stays on this device."))
        }
    }

    private func buildGoogleAccountSection(_ login: GoogleLogin) -> some View {
        Section {
            LabeledContent(String(localized: "Signed in as"), value: login.displayName)

            Button(String(localized: "Use Another Google Account")) {
                Task { await viewModel.signInWithGoogle() }
            }
        } header: {
            Text("Google Account")
        }
    }

    private func buildMissingAccessSection() -> some View {
        Section {
            ForEach(google.disabledFeatures, id: \.self) { feature in
                Label(feature.displayName, systemImage: "xmark.circle")
                    .foregroundStyle(.orange)
            }

            Button(String(localized: "Grant Access")) {
                Task { await viewModel.grantMissingGoogleAccess() }
            }
        } header: {
            Text("Access Not Granted")
        } footer: {
            Text("These stay off because their checkbox was unticked on Google's consent page. Tap Grant Access to allow them.")
        }
    }

    private func buildGooglePickerSection() -> some View {
        Section {
            ForEach(google.items) { item in
                StackTrackedButton(.toggleApp, on: .addAccount) {
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
                Text(viewModel.uiState.providerType == .googlePlay
                     ? String(localized: "Apps")
                     : String(localized: "Projects"))
                Spacer()
                if !google.selectableItems.isEmpty {
                    Button(google.areAllSelected ? String(localized: "Select None") : String(localized: "Select All")) {
                        viewModel.setAllGoogleItemsSelected(!google.areAllSelected)
                    }
                    .font(.footnote)
                    .textCase(nil)
                }
            }
        } footer: {
            Text(viewModel.uiState.providerType == .googlePlay
                 ? String(localized: "One account is added for this Google login. With every app selected, apps you get access to later show up too.")
                 : String(localized: "Each project is added as its own account."))
        }
    }

    private func buildErrorSection(_ error: String) -> some View {
        Section {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .addAccount) {
                dismiss()
                onDismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            if viewModel.uiState.isValidating {
                ProgressView()
            } else {
                Button(String(localized: "Save")) {
                    Task { await viewModel.save() }
                }
                .disabled(!viewModel.uiState.canSave)
            }
        }
    }
}
