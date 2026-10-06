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
                buildNameSection()

                if viewModel.uiState.providerType == .apple {
                    buildAppleCredentialsSection()
                    buildAppleTutorialSection()
                }

                if viewModel.uiState.providerType == .firebase {
                    buildFirebaseCredentialsSection()
                    buildFirebaseTutorialSection()
                }

                if viewModel.uiState.providerType == .googlePlay {
                    buildGooglePlayCredentialsSection()
                    buildGooglePlayTutorialSection()
                }

                if let error = viewModel.uiState.validationError {
                    buildErrorSection(error)
                }
            }
            .navigationTitle(String(localized: "Add Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .disabled(viewModel.uiState.isValidating)
            .onChange(of: viewModel.uiState.isSaved) { _, isSaved in
                if isSaved {
                    onDismiss()
                }
            }
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

                StackPasteButton { viewModel.uiState.issuerID = $0 }
            }

            HStack {
                TextField(
                    String(localized: "Private Key ID"),
                    text: $viewModel.uiState.privateKeyID
                )
                .textContentType(.none)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                StackPasteButton { viewModel.uiState.privateKeyID = $0 }
            }

            StackKeyFileInput(
                title: String(localized: "Private Key (.p8)"),
                text: $viewModel.uiState.privateKey,
                importTitle: String(localized: "Import .p8 file"),
                allowedContentTypes: p8AllowedTypes,
                editorFont: .system(.body, design: .monospaced),
                minEditorHeight: 120
            )
        } header: {
            Text("App Store Connect Credentials")
        } footer: {
            Text("Paste or import the .p8 file content along with its Key ID and Issuer ID.")
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
                allowedContentTypes: [.json]
            )
        } header: {
            Text(header)
        } footer: {
            Text(footer)
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
            Button(String(localized: "Cancel")) {
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
                .disabled(viewModel.uiState.accountName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
