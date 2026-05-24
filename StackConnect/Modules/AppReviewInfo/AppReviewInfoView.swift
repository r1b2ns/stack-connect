import SwiftUI
import UIKit

// MARK: - Factory

@MainActor
struct AppReviewInfoViewFactory {
    static func build(versionId: String, account: AccountModel) -> some View {
        AppReviewInfoEntry(versionId: versionId, account: account)
    }
}

// MARK: - Entry

private struct AppReviewInfoEntry: View {
    let versionId: String
    let account: AccountModel

    @StateObject private var viewModel: AppReviewInfoViewModel

    init(versionId: String, account: AccountModel) {
        self.versionId = versionId
        self.account = account
        _viewModel = StateObject(wrappedValue: AppReviewInfoViewModel(versionId: versionId, account: account))
    }

    var body: some View {
        AppReviewInfoView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppReviewInfoView<ViewModel: AppReviewInfoViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPasswordVisible = false

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "App Review Information"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .disabled(viewModel.uiState.isSaving)
            .task { await viewModel.loadReviewDetail() }
            .onChange(of: viewModel.uiState.didSave) { _, didSave in
                if didSave { dismiss() }
            }
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                buildSignInSection()
                buildContactSection()
                buildNotesSection()

                if let error = viewModel.uiState.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Sign-In Information

    private func buildSignInSection() -> some View {
        Section {
            Toggle(
                String(localized: "Demo Account Required"),
                isOn: $viewModel.uiState.isDemoAccountRequired
            )

            if viewModel.uiState.isDemoAccountRequired {
                HStack {
                    TextField(String(localized: "Demo Account Name"), text: $viewModel.uiState.demoAccountName)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                    copyButton(value: viewModel.uiState.demoAccountName)
                }

                HStack {
                    Group {
                        if isPasswordVisible {
                            TextField(String(localized: "Demo Account Password"), text: $viewModel.uiState.demoAccountPassword)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField(String(localized: "Demo Account Password"), text: $viewModel.uiState.demoAccountPassword)
                                .textContentType(.password)
                        }
                    }
                    passwordVisibilityButton()
                }
            }
        } header: {
            Text("Sign-In Information")
        }
    }

    private func copyButton(value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(value.isEmpty)
    }

    private func passwordVisibilityButton() -> some View {
        Button {
            isPasswordVisible.toggle()
        } label: {
            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contact Information

    private func buildContactSection() -> some View {
        Section {
            TextField(String(localized: "First Name"), text: $viewModel.uiState.contactFirstName)
                .textContentType(.givenName)

            TextField(String(localized: "Last Name"), text: $viewModel.uiState.contactLastName)
                .textContentType(.familyName)

            TextField(String(localized: "Email"), text: $viewModel.uiState.contactEmail)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)

            TextField(String(localized: "Phone"), text: $viewModel.uiState.contactPhone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
        } header: {
            Text("Contact Information")
        }
    }

    // MARK: - Notes

    private func buildNotesSection() -> some View {
        Section {
            TextEditor(text: $viewModel.uiState.notes)
                .frame(minHeight: 100)
        } header: {
            Text("Notes")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.uiState.isSaving {
                ProgressView()
            } else {
                Button(String(localized: "Save")) {
                    Task { await viewModel.save() }
                }
            }
        }
    }
}
