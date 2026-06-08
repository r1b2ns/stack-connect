import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// Phase 4 · Block F · T-F13 — Import .scexport screen (US-W05).
//
// Progressive disclosure form for importing an encrypted .scexport file:
//   Step 1 — SELECT FILE: file path display + Browse button (Win32 dialog).
//   Step 2 — PASSWORD: password field + Decrypt button. Shown after a file is
//            selected. Error banner appears here for decrypt/validation failures.
//   Step 3 — CONFIRM: pre-populated (editable) account name + Import button.
//            Shown after successful decryption.
//
// The view binds to `WindowsImportAccountModel` (T-F12) which owns the 3-step
// state machine, file reading, decryption (AccountCrypto), JSON validation,
// provider mismatch detection, duplicate credential checks, and persistence.
// The view is purely declarative — all mutations flow through the model.
//
// Layout follows the Windows app convention: content capped at 860px, padded
// 16px, with a `ScrollView` + `VStack`. Error banners use the red left-border
// InfoBar style matching the other account screens.
//
// On successful import (`model.didFinishImport == true`) the view calls
// `coordinator.pop()` to return to the previous screen.

struct WindowsImportAccountView: View {

    /// Navigation coordinator — Back and import-success pop the route stack.
    @State private var coordinator: WindowsHomeCoordinator

    /// The import model. Observed via `@State` so the view redraws when the
    /// model's `@Published` properties change (step, filePath, errorMessage, etc).
    @State private var model: WindowsImportAccountModel

    init(
        coordinator: WindowsHomeCoordinator,
        storage: PersistentStorable,
        secrets: KeyStorable
    ) {
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: WindowsImportAccountModel(
            expectedProvider: .apple,
            storage: storage,
            secrets: secrets
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                buildBackButton()
                buildHeroSection()
                buildStep1()
                buildStep2()
                buildErrorBanner()
                buildStep3()
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
    }

    // MARK: - Back button (AC-1)

    /// "< Back" at the top of the screen. Within the import steps (step 2+),
    /// tapping Back goes back within the wizard. At step 1, it pops the route.
    private func buildBackButton() -> some View {
        WindowsBackButtonView(onBack: {
            if model.step == .selectFile {
                coordinator.pop()
            } else {
                model.goBack()
            }
        })
    }

    // MARK: - Hero Section

    /// The hero section with a document icon and descriptive text, shown above
    /// the steps.
    private func buildHeroSection() -> some View {
        VStack(spacing: 8) {
            Text("\u{1F4C4}")
                .font(.largeTitle)
            Text("Import an encrypted .scexport file containing your account credentials.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step 1: Select File (AC-1, AC-4, AC-5)

    /// Step 1 — SELECT FILE: shows the selected file name (or placeholder) and
    /// a Browse button that opens the Win32 file picker. Always visible.
    private func buildStep1() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEP 1 — SELECT FILE")
                .fontWeight(.bold)
                .foregroundColor(.gray)

            // File name display
            HStack(spacing: 8) {
                Text(fileDisplayName)
                    .foregroundColor(model.filePath.isEmpty ? .gray : .black)
                Spacer()
            }

            // Browse button — opens Win32 GetOpenFileName dialog (AC-1)
            Button("\u{2193} Browse\u{2026}") {
                if let path = WindowsFilePicker.openFile(
                    title: "Select .scexport File",
                    filters: [
                        ("Encrypted Export (*.scexport)", "*.scexport"),
                        ("All Files (*.*)", "*.*"),
                    ]
                ) {
                    model.filePath = path
                    // Auto-advance to step 2 when a file is selected via the
                    // picker (the file existence is verified inside advanceStep).
                    Task {
                        await model.advanceStep()
                    }
                }
            }
            .disabled(model.isProcessing)
        }
        .padding(12)
        .background(Color(white: 0.96))
        .cornerRadius(8)
    }

    /// The display name for the selected file. Shows just the file name (last
    /// path component) if a file is selected, or a placeholder if not.
    private var fileDisplayName: String {
        let path = model.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "No file selected" }
        // Extract the last path component (file name) for display.
        if let lastSlash = path.lastIndex(of: "\\") ?? path.lastIndex(of: "/") {
            return String(path[path.index(after: lastSlash)...])
        }
        return path
    }

    // MARK: - Step 2: Password + Decrypt (AC-1, AC-6)

    /// Step 2 — PASSWORD: password text field + Decrypt button. Only shown
    /// after a file has been selected (step >= enterPassword).
    @ViewBuilder
    private func buildStep2() -> some View {
        if model.step == .enterPassword || model.step == .confirmName {
            VStack(alignment: .leading, spacing: 8) {
                Text("STEP 2 — PASSWORD")
                    .fontWeight(.bold)
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                    SecureField("Enter decryption password", text: $model.password)
                        .disabled(model.isProcessing || model.step == .confirmName)
                }

                if model.step == .enterPassword {
                    HStack {
                        Spacer()
                        if model.isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Decrypting...")
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Button("Decrypt") {
                                Task {
                                    await model.advanceStep()
                                }
                            }
                            .disabled(model.password.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(white: 0.96))
            .cornerRadius(8)
        }
    }

    // MARK: - Error Banner (AC-4, AC-5, AC-6, AC-7, AC-8, AC-9)

    /// Inline error banner shown when the model has a non-nil `errorMessage`.
    /// Uses the red left-border InfoBar style consistent with other account
    /// screens (WindowsCreateAppleAccountView, WindowsAccountsListView).
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

    // MARK: - Step 3: Confirm Name + Import (AC-2, AC-3)

    /// Step 3 — CONFIRM: pre-populated account name (editable) + Import button.
    /// Only shown after successful decryption (step == confirmName).
    @ViewBuilder
    private func buildStep3() -> some View {
        if model.step == .confirmName {
            VStack(alignment: .leading, spacing: 8) {
                Text("STEP 3 — CONFIRM")
                    .fontWeight(.bold)
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Name")
                    TextField("Account Name", text: $model.accountName)
                        .disabled(model.isProcessing)
                }

                HStack {
                    Spacer()
                    if model.isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Importing...")
                                .foregroundColor(.gray)
                        }
                    } else {
                        Button("Import Account") {
                            Task {
                                await model.advanceStep()
                                // AC-3: on successful import, pop to the list.
                                if model.didFinishImport {
                                    coordinator.pop()
                                }
                            }
                        }
                        .disabled(model.accountName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(12)
            .background(Color(white: 0.96))
            .cornerRadius(8)
        }
    }
}
