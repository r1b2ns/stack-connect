import SwiftUI
import StackCoreRust

// MARK: - Factory

@MainActor
struct AppleIdSignInViewFactory {
    /// The "Sign in with Apple ID" screens, inside the caller's navigation
    /// stack. `onFinished` runs once the accounts were added (`.addAccounts`)
    /// or the session was replaced (`.signInAgain`).
    static func build(mode: AppleIdSignInMode, onFinished: @escaping () -> Void) -> some View {
        AppleIdSignInEntry(mode: mode, onFinished: onFinished)
    }
}

// MARK: - Entry

private struct AppleIdSignInEntry: View {
    let onFinished: () -> Void

    @StateObject private var viewModel: AppleIdSignInViewModel

    init(mode: AppleIdSignInMode, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        _viewModel = StateObject(wrappedValue: AppleIdSignInViewModel(mode: mode))
    }

    var body: some View {
        AppleIdSignInView(viewModel: viewModel, onFinished: onFinished)
    }
}

// MARK: - View

/// Three screens in one place, switched by `uiState.step`: the Apple ID and
/// password, the two-factor code, and (Add Account) the teams to add.
struct AppleIdSignInView<ViewModel: AppleIdSignInViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let onFinished: () -> Void

    @Environment(\.openURL) private var openURL
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var state: AppleIdSignInUiState { viewModel.uiState }

    var body: some View {
        Form {
            switch state.step {
            case .credentials:
                buildCredentialsContent()
            case .code:
                buildCodeContent()
            case .teams, .finished:
                buildTeamsContent()
            case .needsAcknowledgement:
                buildAcknowledgementContent()
            }

            if let error = state.errorMessage {
                buildErrorSection(error)
            }
        }
        .navigationTitle(buildTitle())
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(.appleIdSignIn)
        .toolbar { buildToolbar() }
        .navigationBarBackButtonHidden(state.step == .code)
        .disabled(state.isWorking && state.step != .code)
        .animation(.default, value: state.step)
        .onChange(of: state.step) { _, step in
            if step == .finished { onFinished() }
        }
        .onChange(of: state.email) { _, _ in viewModel.emailDidChange() }
        .task { await viewModel.signInWithSavedPasswordIfAvailable() }
        .onDisappear { viewModel.discard() }
    }

    private func buildTitle() -> String {
        switch state.step {
        case .credentials, .needsAcknowledgement: return String(localized: "Sign in with Apple ID")
        case .code:                               return String(localized: "Two-Factor Code")
        case .teams, .finished:                   return String(localized: "Choose Teams")
        }
    }

    // MARK: - Screen 1: Apple ID and password

    @ViewBuilder
    private func buildCredentialsContent() -> some View {
        Section {
            TextField(String(localized: "Apple ID"), text: $viewModel.uiState.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!state.isEmailEditable)
                .foregroundStyle(state.isEmailEditable ? .primary : .secondary)
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

            if state.usesSavedPassword {
                buildSavedPasswordRow()
            } else {
                SecureField(String(localized: "Password"), text: $viewModel.uiState.password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await viewModel.signIn() } }
            }
        } header: {
            Text("Apple ID")
        } footer: {
            if case .signInAgain = state.mode {
                Text("Sign in again with the same Apple ID. Its App Store Connect accounts start working again.")
            } else {
                Text("Use the Apple ID you sign in to App Store Connect with. You can add any of its teams next.")
            }
        }

        if !state.usesSavedPassword {
            buildSavePasswordSection()
        }

        if let notice = state.notice {
            Section {
                StackNoticeRow(text: notice, style: .info)
            }
        }

        Section {
            StackNoticeRow(
                text: String(localized: "StackConnect sends your password only to Apple. It's saved only if you choose to, in the Keychain on this device only, never synced or exported."),
                style: .privacy
            )
        }

        Section {
            StackSignInButton(
                title: String(localized: "Continue"),
                systemImage: "apple.logo",
                isLoading: state.isWorking
            ) {
                Task { await viewModel.signIn() }
            }
            .disabled(!state.canSignIn)
        } footer: {
            Text("Accounts with a security key as their second factor can't sign in here yet. Use an App Store Connect API key instead.")
        }
    }

    /// "Save password on this device". Hidden while the saved password is used.
    private func buildSavePasswordSection() -> some View {
        Section {
            Toggle(String(localized: "Save password on this device"), isOn: Binding(
                get: { viewModel.uiState.savesPassword },
                set: { viewModel.setSavesPassword($0) }
            ))
        } footer: {
            Text("You'll only need the verification code next time. Stored in this device's Keychain.")
        }
    }

    /// Stands in for the password field when the saved password is used.
    @ViewBuilder
    private func buildSavedPasswordRow() -> some View {
        Label(String(localized: "Using the password saved on this device"), systemImage: "key.fill")
            .foregroundStyle(.secondary)
        if !state.savesPassword {
            // "Save password on this device" was turned off before the saved
            // password row appeared: the off still applies.
            StackNoticeRow(
                text: String(localized: "Save password is off: this saved password will be removed once you're signed in."),
                style: .info
            )
        }
        buildUseDifferentPasswordButton()
    }

    private func buildUseDifferentPasswordButton() -> some View {
        Button(String(localized: "Use a Different Password")) {
            viewModel.useDifferentPassword()
            focusedField = .password
        }
        .disabled(state.isWorking)
    }

    // MARK: - Screen 2: two-factor code

    @ViewBuilder
    private func buildCodeContent() -> some View {
        if state.usesSavedPassword {
            Section {
                LabeledContent(String(localized: "Apple ID"), value: state.email)
                buildUseDifferentPasswordButton()
            } footer: {
                Text("Signed in with the password saved on this device. Only the code is left.")
            }
        }

        Section {
            StackVerificationCodeField(
                code: state.code,
                length: state.codeLength,
                isError: state.codeError != nil,
                isDisabled: state.isWorking || state.codeMethod == nil
            ) { typed in
                Task { await viewModel.updateCode(typed) }
            }
            .listRowBackground(Color.clear)

            if let codeError = state.codeError {
                Label(codeError, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Code")
        } footer: {
            if let notice = state.notice {
                Text(notice)
            }
        }

        Section {
            if state.isWorking {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Checking with Apple…")
                        .foregroundStyle(.secondary)
                }
            } else {
                StackSignInButton(title: String(localized: "Verify"), systemImage: "checkmark.shield") {
                    Task { await viewModel.submitCode() }
                }
                .disabled(!state.canSubmitCode)
            }
        }

        if !state.phones.isEmpty {
            buildSmsSection()
        }
    }

    private func buildSmsSection() -> some View {
        Section {
            ForEach(state.phones, id: \.id) { phone in
                StackChoiceRow(
                    title: phone.maskedNumber,
                    subtitle: phone.mode == "voice" ? String(localized: "Phone call") : String(localized: "Text message"),
                    icon: "iphone",
                    isSelected: state.codeMethod == .phone(phoneId: phone.id)
                ) {
                    Task { await viewModel.requestSms(phoneId: phone.id) }
                }
                .disabled(state.isWorking)
            }
        } header: {
            Text("Send SMS Instead")
        } footer: {
            Text("Didn't get a code on your devices? Pick a trusted phone number and Apple sends one to it.")
        }
    }

    // MARK: - Screen 3: teams

    @ViewBuilder
    private func buildTeamsContent() -> some View {
        if let notice = state.notice {
            Section {
                StackNoticeRow(text: notice, style: .success)
            }
        }

        if !state.teams.isEmpty {
            Section {
                ForEach(state.teams) { item in
                    StackTrackedButton(.toggleTeam, on: .appleIdSignIn) {
                        viewModel.toggleTeam(item.id)
                    } label: {
                        StackSelectableRow(
                            title: item.team.name,
                            subtitle: item.team.publicProviderId,
                            isSelected: state.selectedTeamIds.contains(item.id),
                            note: item.isAlreadyAdded ? String(localized: "Already added") : nil
                        )
                    }
                    .disabled(item.isAlreadyAdded)
                }
            } header: {
                HStack {
                    Text("Teams")
                    Spacer()
                    if state.selectableTeams.count > 1 {
                        Button(state.areAllTeamsSelected ? String(localized: "Select None") : String(localized: "Select All")) {
                            viewModel.setAllTeamsSelected(!state.areAllTeamsSelected)
                        }
                        .font(.footnote)
                        .textCase(nil)
                    }
                }
            } footer: {
                Text("Each team is added as its own account. They share this sign-in: when it expires, you sign in once for all of them.")
            }
        }
    }

    // MARK: - Needs acknowledgement

    @ViewBuilder
    private func buildAcknowledgementContent() -> some View {
        Section {
            Label {
                Text("This Apple ID needs your attention before it can sign in here: Apple asks you to review or update something on your account (for example new terms, or upgrading its security). Sign in at appleid.apple.com, follow the steps there, then try again.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Action Needed")
        }

        Section {
            Button(String(localized: "Open appleid.apple.com")) {
                if let url = viewModel.openAppleIdWebsite() { openURL(url) }
            }
            Button(String(localized: "Try Again")) {
                viewModel.startOver()
            }
        }
    }

    // MARK: - Shared

    private func buildErrorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if state.step == .code {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Back")) { viewModel.startOver() }
                    .disabled(state.isWorking)
            }
        }
        if state.step == .teams {
            ToolbarItem(placement: .confirmationAction) {
                if state.isWorking {
                    ProgressView()
                } else {
                    Button(String(localized: "Save")) {
                        Task { await viewModel.save() }
                    }
                    .disabled(!state.canSave)
                }
            }
        }
    }
}
