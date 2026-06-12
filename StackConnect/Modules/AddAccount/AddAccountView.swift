import SwiftUI
import UIKit
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
    @State private var showingP8FilePicker = false
    @State private var showingJSONFilePicker = false

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

                buildPasteButton { viewModel.uiState.issuerID = $0 }
            }

            HStack {
                TextField(
                    String(localized: "Private Key ID"),
                    text: $viewModel.uiState.privateKeyID
                )
                .textContentType(.none)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                buildPasteButton { viewModel.uiState.privateKeyID = $0 }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Private Key (.p8)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    buildPasteButton { viewModel.uiState.privateKey = $0 }
                }

                TextEditor(text: $viewModel.uiState.privateKey)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    showingP8FilePicker = true
                } label: {
                    Label(String(localized: "Import .p8 file"), systemImage: "doc.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .fileImporter(
                    isPresented: $showingP8FilePicker,
                    allowedContentTypes: p8AllowedTypes
                ) { result in
                    handleFileImport(result: result) { content in
                        viewModel.uiState.privateKey = content
                    }
                }
            }
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
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Service Account Key (JSON)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    buildPasteButton { viewModel.uiState.firebaseJSON = $0 }
                }

                TextEditor(text: $viewModel.uiState.firebaseJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 200)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    showingJSONFilePicker = true
                } label: {
                    Label(String(localized: "Import .json file"), systemImage: "doc.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .fileImporter(
                    isPresented: $showingJSONFilePicker,
                    allowedContentTypes: [.json]
                ) { result in
                    handleFileImport(result: result) { content in
                        viewModel.uiState.firebaseJSON = content
                    }
                }
            }
        } header: {
            Text("Firebase Credentials")
        } footer: {
            Text("Paste or import the full JSON content of your Google Service Account key file.")
        }
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
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Service Account Key (JSON)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    buildPasteButton { viewModel.uiState.googlePlayJSON = $0 }
                }

                TextEditor(text: $viewModel.uiState.googlePlayJSON)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 200)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Google Play Credentials")
        } footer: {
            Text("Paste the full JSON content of your Google Service Account key file. The service account must have access to the Google Play Developer API. Create it at console.cloud.google.com and link it in play.google.com/console under Setup > API access.")
        }
    }

    private func handleFileImport(
        result: Result<URL, Error>,
        assign: (String) -> Void
    ) {
        guard case .success(let url) = result else {
            Log.print.error("[AddAccount] File import failed")
            return
        }
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer {
            if needsRelease { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            assign(content)
        } catch {
            Log.print.error("[AddAccount] Failed to read imported file: \(error.localizedDescription)")
        }
    }

    private func buildPasteButton(onPaste: @escaping (String) -> Void) -> some View {
        Button {
            if let text = UIPasteboard.general.string {
                onPaste(text)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
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
