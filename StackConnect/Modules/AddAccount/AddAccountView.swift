import SwiftUI
import UIKit

// MARK: - Factory

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

    var body: some View {
        NavigationStack {
            Form {
                buildNameSection()

                if viewModel.uiState.providerType == .apple {
                    buildAppleCredentialsSection()
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
            }
        } header: {
            Text("App Store Connect Credentials")
        } footer: {
            Text("You can generate API keys at appstoreconnect.apple.com under Users and Access > Integrations > App Store Connect API.")
        }
    }

    private func buildPasteButton(onPaste: @escaping (String) -> Void) -> some View {
        Button {
            if let text = UIPasteboard.general.string {
                onPaste(text)
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
