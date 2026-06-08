import Foundation
import SwiftCrossUI
import StackHomeCore
import WindowsAppCore
import StackProtocols

// Phase 4 · Block F · T-F11 — Create Firebase Account form (US-W04, design §F).
//
// A form screen that lets the user create a Firebase account by entering an
// Account Name and pasting/browsing a Service Account JSON key. Validation is
// fully delegated to `WindowsCreateAccountModel` (T-F09): empty JSON, invalid
// JSON, and duplicate credential checks are all handled there. On successful
// save, credentials go to `WindowsCredentialStorable` (via the injected
// `KeyStorable`) and the `AccountModel` goes to SQLite (via `PersistentStorable`),
// then the view pops back to the accounts list.
//
// Layout follows the same 860px-max / 16px-padded ScrollView pattern used across
// all Windows form screens. The error banner uses the red-left-border InfoBar
// style from `WindowsAlertBannerView`.

struct WindowsCreateFirebaseAccountView: View {

    @State private var model: WindowsCreateAccountModel
    @State private var coordinator: WindowsHomeCoordinator

    init(
        coordinator: WindowsHomeCoordinator,
        storage: PersistentStorable,
        secrets: KeyStorable
    ) {
        _coordinator = State(wrappedValue: coordinator)
        _model = State(
            wrappedValue: WindowsCreateAccountModel(
                providerType: .firebase,
                storage: storage,
                secrets: secrets
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                buildToolbar()
                buildGeneralSection()
                buildFirebaseCredentialsSection()
                buildErrorBanner()
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
    }

    // MARK: - Toolbar (Back + Save)

    /// Header row: "< Back" on the left, "Save" button on the right.
    /// Back pops without saving. Save triggers the async save flow (AC-1).
    /// While saving, the button shows a loading indicator and the form is
    /// disabled.
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
                        await model.saveFirebaseAccount()
                        if model.isSaved {
                            coordinator.pop()
                        }
                    }
                }
                .disabled(
                    model.accountName.trimmingCharacters(in: .whitespaces).isEmpty
                    || model.serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    // MARK: - General Section

    /// The "GENERAL" section containing the Account Name text field (AC-1).
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

    // MARK: - Firebase Credentials Section

    /// The "FIREBASE CREDENTIALS" section with Service Account JSON TextEditor,
    /// Paste button, and Browse button (AC-1).
    private func buildFirebaseCredentialsSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FIREBASE CREDENTIALS")
                .fontWeight(.bold)
                .foregroundColor(.gray)

            HStack {
                Text("Service Account Key (JSON)")
                Spacer()
                Button("Paste") {
                    if let text = WindowsClipboard.getText() {
                        model.serviceAccountJSON = text
                    }
                }
                .disabled(model.isSaving)
            }

            TextEditor(text: $model.serviceAccountJSON)
                .frame(minHeight: 200)
                .disabled(model.isSaving)

            Button("+ Browse...") {
                if let path = WindowsFilePicker.openFile(
                    title: "Select Service Account JSON",
                    filters: [
                        ("JSON Files (*.json)", "*.json"),
                        ("All Files (*.*)", "*.*"),
                    ]
                ) {
                    model.loadJSONFromFile(at: path)
                }
            }
            .disabled(model.isSaving)
        }
    }

    // MARK: - Error Banner

    /// Inline error banner shown when the model has a non-nil `errorMessage`.
    /// Uses the red left-border InfoBar style matching the accounts list
    /// error pattern (AC-2, AC-3, AC-5).
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
