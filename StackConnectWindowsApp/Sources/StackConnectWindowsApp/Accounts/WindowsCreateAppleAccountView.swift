import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// Phase 4 · Block F · T-F10 — Create Apple Account form (US-W03).
//
// A scrollable form for adding a new Apple (ASC) account:
//   GENERAL section — Account Name text field.
//   APP STORE CONNECT CREDENTIALS section — Issuer ID, Private Key ID
//   (each with a Paste button), Private Key TextEditor (monospaced,
//   minHeight 120) with Paste and Browse buttons.
//
// The view binds to `WindowsCreateAccountModel` (T-F09) which owns field
// validation, PEM sanitization, duplicate credential detection, and the
// persistence flow (SQLite + WindowsCredentialStorable). The view is
// purely declarative — all mutations flow through the model's intents.
//
// Paste buttons read from `WindowsClipboard.getText()` (T-F15). The
// Browse button opens a Win32 file picker via `WindowsFilePicker.openFile`
// (T-F14) filtered to *.p8 / *.* and reads the file content into the
// Private Key field.
//
// Error banner: red left-border InfoBar style (matching the accounts list
// pattern). The banner shows validation errors, duplicate-credential
// warnings, and save failures.
//
// Back without saving writes no data (AC-8). Save success triggers
// `coordinator.pop()` to return to the accounts list (AC-3).

struct WindowsCreateAppleAccountView: View {

    /// Navigation coordinator — Back/Save-success pop the route stack.
    @State private var coordinator: WindowsHomeCoordinator

    /// The create-account model. Observed via `@State` so the view redraws
    /// when the model's `@Published` properties change.
    @State private var model: WindowsCreateAccountModel

    init(
        coordinator: WindowsHomeCoordinator,
        storage: PersistentStorable,
        secrets: KeyStorable
    ) {
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: WindowsCreateAccountModel(
            providerType: .apple,
            storage: storage,
            secrets: secrets
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                buildToolbar()
                buildGeneralSection()
                buildCredentialsSection()
                buildErrorBanner()
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
    }

    // MARK: - Toolbar (AC-1, AC-8)

    /// Header row: "< Back" on the left, "Save" button on the right.
    /// Back pops without saving (AC-8). Save triggers the async save flow
    /// (AC-2). While saving, the button shows a loading indicator and the
    /// form is disabled.
    private func buildToolbar() -> some View {
        HStack {
            WindowsBackButtonView(onBack: { coordinator.pop() })
            Spacer()
            if model.isSaving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Saving...")
                        .foregroundColor(.gray)
                }
            } else {
                Button("Save") {
                    Task {
                        await model.saveAppleAccount()
                        // AC-3: successful save pops to account list.
                        if model.isSaved {
                            coordinator.pop()
                        }
                    }
                }
                .disabled(!model.isFormComplete)
            }
        }
    }

    // MARK: - General Section (AC-1)

    /// The "GENERAL" section containing the Account Name text field.
    private func buildGeneralSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GENERAL")
                .fontWeight(.bold)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 4) {
                Text("Account Name")
                TextField("Account Name", text: $model.accountName)
                    .disabled(model.isSaving)
            }
        }
    }

    // MARK: - Credentials Section (AC-1)

    /// The "APP STORE CONNECT CREDENTIALS" section containing Issuer ID,
    /// Private Key ID, and Private Key fields, each with Paste and/or
    /// Browse actions.
    private func buildCredentialsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APP STORE CONNECT CREDENTIALS")
                .fontWeight(.bold)
                .foregroundColor(.gray)

            buildIssuerIDField()
            buildPrivateKeyIDField()
            buildPrivateKeyField()
        }
    }

    // MARK: - Issuer ID field

    /// Issuer ID text field with a Paste button that reads from the system
    /// clipboard (T-F15).
    private func buildIssuerIDField() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Issuer ID")
            HStack(spacing: 8) {
                TextField("Issuer ID", text: $model.issuerID)
                    .disabled(model.isSaving)
                Button("Paste") {
                    if let text = WindowsClipboard.getText() {
                        model.issuerID = text
                    }
                }
                .disabled(model.isSaving)
            }
        }
    }

    // MARK: - Private Key ID field

    /// Private Key ID text field with a Paste button.
    private func buildPrivateKeyIDField() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Private Key ID")
            HStack(spacing: 8) {
                TextField("Private Key ID", text: $model.privateKeyID)
                    .disabled(model.isSaving)
                Button("Paste") {
                    if let text = WindowsClipboard.getText() {
                        model.privateKeyID = text
                    }
                }
                .disabled(model.isSaving)
            }
        }
    }

    // MARK: - Private Key field (TextEditor + Paste + Browse)

    /// Private Key (.p8) section: a label row with Paste, a monospaced
    /// TextEditor (minHeight 120), and a Browse button that opens the
    /// Win32 file picker for *.p8 files (T-F14).
    private func buildPrivateKeyField() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Private Key (.p8)")
                Spacer()
                Button("Paste") {
                    if let text = WindowsClipboard.getText() {
                        model.privateKey = text
                    }
                }
                .disabled(model.isSaving)
            }

            TextEditor(text: $model.privateKey)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .disabled(model.isSaving)

            Button("+ Browse...") {
                if let path = WindowsFilePicker.openFile(
                    title: "Select Private Key",
                    filters: [
                        ("Auth Key Files (*.p8)", "*.p8"),
                        ("All Files (*.*)", "*.*"),
                    ]
                ) {
                    model.loadPrivateKeyFromFile(at: path)
                }
            }
            .disabled(model.isSaving)
        }
    }

    // MARK: - Error Banner (AC-4, AC-5, AC-6)

    /// Inline error banner shown when the model has a non-nil `errorMessage`.
    /// Uses the red left-border InfoBar style matching the accounts list
    /// error pattern.
    @ViewBuilder
    private func buildErrorBanner() -> some View {
        if let message = model.errorMessage {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(message)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(12)
            }
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

}
