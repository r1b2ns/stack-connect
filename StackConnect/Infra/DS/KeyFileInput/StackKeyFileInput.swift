import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Key File Input

/// Reusable credential-file input for `Form`s:
/// `{caption} ——— {paste}` over a monospaced editor, followed by an
/// "Import …" button backed by `.fileImporter`.
///
/// Used by Add Account for the App Store Connect `.p8` key and the Firebase /
/// Google Play service-account JSON keys. Drop it inside a `Section`; the
/// section's header/footer stay with the caller.
///
/// ```swift
/// Section {
///     StackKeyFileInput(
///         title: String(localized: "Service Account Key (JSON)"),
///         text: $json,
///         importTitle: String(localized: "Import .json file"),
///         allowedContentTypes: [.json]
///     )
/// } footer: { … }
/// ```
///
/// The imported file is read as UTF-8 into `text`. Its content is never logged —
/// these files hold private keys.
struct StackKeyFileInput: View {

    let title: String
    @Binding var text: String
    let importTitle: String
    let allowedContentTypes: [UTType]
    var editorFont: Font = .system(.caption, design: .monospaced)
    var minEditorHeight: CGFloat = 200

    @State private var isImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                StackPasteButton { text = $0 }
            }

            TextEditor(text: $text)
                .font(editorFont)
                .frame(minHeight: minEditorHeight)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                isImporterPresented = true
            } label: {
                Label(importTitle, systemImage: "doc.badge.plus")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: allowedContentTypes
            ) { result in
                handleImport(result)
            }
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            Log.print.error("[StackKeyFileInput] File import failed")
            return
        }
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer {
            if needsRelease { url.stopAccessingSecurityScopedResource() }
        }
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Log.print.error("[StackKeyFileInput] Failed to read imported file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Paste Button

/// Borderless clipboard icon that hands the current pasteboard string to
/// `onPaste` (with a light haptic). Does nothing when the pasteboard holds no text.
struct StackPasteButton: View {

    let onPaste: (String) -> Void

    var body: some View {
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
        .accessibilityLabel(String(localized: "Paste"))
    }
}
