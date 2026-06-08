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
        .onChange(of: model.isSaved) {
            if model.isSaved {
                coordinator.pop()
            }
        }
    }

    // MARK: - Toolbar (Back + Save)

    /// Top bar: "< Back" on the left, Save button on the right. Save is disabled
    /// when the form is incomplete or while saving is in progress (AC-1).
    private func buildToolbar() -> some View {
        HStack {
            WindowsBackButtonView(onBack: { coordinator.pop() })

            Spacer()

            if model.isSaving {
                Text("Saving...")
            } else {
                Button("Save") {
                    Task {
                        await model.saveFirebaseAccount()
                    }
                }
                .disabled(!isFormComplete)
            }
        }
    }

    // MARK: - General Section

    /// The "General" section containing the Account Name text field (AC-1).
    private func buildGeneralSection() -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("GENERAL")
                    .fontWeight(.semibold)
                Spacer()
            }

            HStack {
                Text("Account Name")
                Spacer()
            }
            TextField("Account Name", text: $model.accountName)
                .disabled(model.isSaving)
        }
    }

    // MARK: - Firebase Credentials Section

    /// The "Firebase Credentials" section with Service Account JSON TextEditor,
    /// Paste button, and Browse button (AC-1).
    private func buildFirebaseCredentialsSection() -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("FIREBASE CREDENTIALS")
                    .fontWeight(.semibold)
                Spacer()
            }

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

            HStack {
                Button("+ Browse...") {
                    if let path = WindowsFilePicker.openFile(
                        title: "Select Service Account JSON",
                        filters: [
                            ("JSON Files (*.json)", "*.json"),
                            ("All Files (*.*)", "*.*"),
                        ]
                    ) {
                        loadFileContents(at: path)
                    }
                }
                .disabled(model.isSaving)
                Spacer()
            }
        }
    }

    // MARK: - Error Banner

    /// Red-left-border InfoBar error banner. Shown only when the model has a
    /// non-nil error message (AC-2, AC-3, AC-5).
    @ViewBuilder
    private func buildErrorBanner() -> some View {
        if let error = model.errorMessage {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.red)
                    .frame(width: 4)
                    .cornerRadius(8)

                VStack(spacing: 8) {
                    HStack {
                        Text(error)
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .padding(12)
            }
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

    // MARK: - Helpers

    /// Whether the form has enough data to attempt a save. The actual validation
    /// (JSON parsing, duplicate detection) lives in the model; this only gates
    /// the Save button so the user gets immediate visual feedback.
    private var isFormComplete: Bool {
        let nameFilled = !model.accountName.trimmingCharacters(in: .whitespaces).isEmpty
        let jsonFilled = !model.serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return nameFilled && jsonFilled
    }

    /// Reads a file from disk and loads its content into the JSON text editor.
    private func loadFileContents(at path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else {
            model.errorMessage = "Could not read file."
            return
        }
        model.serviceAccountJSON = content
    }
}
