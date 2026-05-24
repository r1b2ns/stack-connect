import SwiftUI
import UIKit

// MARK: - Factory

@MainActor
struct BetaAppReviewInfoViewFactory {
    static func build(appId: String, account: AccountModel) -> some View {
        BetaAppReviewInfoEntry(appId: appId, account: account)
    }
}

// MARK: - Entry

private struct BetaAppReviewInfoEntry: View {
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: BetaAppReviewInfoViewModel

    init(appId: String, account: AccountModel) {
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: BetaAppReviewInfoViewModel(appId: appId, account: account))
    }

    var body: some View {
        BetaAppReviewInfoView(viewModel: viewModel)
    }
}

// MARK: - View

struct BetaAppReviewInfoView<ViewModel: BetaAppReviewInfoViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPasswordVisible = false

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Test Information"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .disabled(viewModel.uiState.isSaving)
            .task { await viewModel.load() }
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
                buildBetaInfoSection()
                buildContactSection()
                buildSignInSection()

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

    // MARK: - Beta App Description / Feedback Email

    private func buildBetaInfoSection() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "Beta App Description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.uiState.isBetaDescriptionInvalid {
                        invalidIcon()
                    }
                }
                TextEditor(text: $viewModel.uiState.betaDescription)
                    .frame(minHeight: 100)
            }

            HStack {
                TextField(String(localized: "Feedback Email"), text: $viewModel.uiState.feedbackEmail)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                if viewModel.uiState.isFeedbackEmailInvalid {
                    invalidIcon()
                }
            }
        }
    }

    private func invalidIcon() -> some View {
        Image(systemName: "info.circle.fill")
            .foregroundStyle(.red)
    }

    // MARK: - Contact Information

    private func buildContactSection() -> some View {
        Section {
            HStack {
                TextField(String(localized: "First Name"), text: $viewModel.uiState.contactFirstName)
                    .textContentType(.givenName)
                if viewModel.uiState.isContactFirstNameInvalid {
                    invalidIcon()
                }
            }

            HStack {
                TextField(String(localized: "Last Name"), text: $viewModel.uiState.contactLastName)
                    .textContentType(.familyName)
                if viewModel.uiState.isContactLastNameInvalid {
                    invalidIcon()
                }
            }

            HStack {
                TextField(String(localized: "Phone Number"), text: $viewModel.uiState.contactPhone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .onChange(of: viewModel.uiState.contactPhone) { _, newValue in
                        let filtered = sanitizePhone(newValue)
                        if filtered != newValue {
                            viewModel.uiState.contactPhone = filtered
                        }
                    }
                if viewModel.uiState.isContactPhoneInvalid {
                    invalidIcon()
                }
            }

            HStack {
                TextField(String(localized: "Email"), text: $viewModel.uiState.contactEmail)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                if viewModel.uiState.isContactEmailInvalid {
                    invalidIcon()
                }
            }
        } header: {
            Text("Contact Information")
        } footer: {
            Text("Use international format with country code, e.g. +5511999999999.")
        }
    }

    private func sanitizePhone(_ raw: String) -> String {
        var result = ""
        for (index, character) in raw.enumerated() {
            if character == "+" && index == 0 {
                result.append(character)
            } else if character.isNumber {
                result.append(character)
            }
        }
        return result
    }

    // MARK: - Sign-In Information

    private func buildSignInSection() -> some View {
        Section {
            Toggle(
                String(localized: "Sign-In Required"),
                isOn: $viewModel.uiState.isDemoAccountRequired
            )

            if viewModel.uiState.isDemoAccountRequired {
                HStack {
                    TextField(String(localized: "User Name"), text: $viewModel.uiState.demoAccountName)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    copyButton(value: viewModel.uiState.demoAccountName)
                }

                HStack {
                    Group {
                        if isPasswordVisible {
                            TextField(String(localized: "Password"), text: $viewModel.uiState.demoAccountPassword)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField(String(localized: "Password"), text: $viewModel.uiState.demoAccountPassword)
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
