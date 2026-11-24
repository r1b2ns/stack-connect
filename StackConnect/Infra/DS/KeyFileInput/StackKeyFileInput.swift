import SwiftUI
import UIKit
import UniformTypeIdentifiers
import StackProtocols

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
///
/// Pass `trackingScreen` to send `button_tap` events (`.paste` / `.importFile`)
/// for the paste and import buttons on that screen. Only the tap is tracked,
/// never the key content.
struct StackKeyFileInput: View {

    let title: String
    @Binding var text: String
    let importTitle: String
    let allowedContentTypes: [UTType]
    var editorFont: Font = .system(.caption, design: .monospaced)
    var minEditorHeight: CGFloat = 200
    var trackingScreen: AnalyticsScreen?

    @State private var isImporterPresented = false
    @Environment(\.analytics) private var analytics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                StackPasteButton(trackingScreen: trackingScreen) { text = $0 }
            }

            TextEditor(text: $text)
                .font(editorFont)
                .frame(minHeight: minEditorHeight)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                if let trackingScreen {
                    analytics.track(.buttonTap(.importFile, on: trackingScreen))
                }
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
            // Network audit: the event of a file read in, never its content.
            NetworkAuditRecorder.shared?.recordFileImport(
                fileName: url.lastPathComponent,
                byteCount: Int64(text.utf8.count)
            )
        } catch {
            Log.print.error("[StackKeyFileInput] Failed to read imported file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Paste Button

/// Borderless clipboard icon that hands the current pasteboard string to
/// `onPaste` (with a light haptic). Does nothing when the pasteboard holds no text.
/// When `trackingScreen` is set, each tap sends a `.paste` `button_tap` on it.
struct StackPasteButton: View {

    var trackingScreen: AnalyticsScreen?
    let onPaste: (String) -> Void

    @Environment(\.analytics) private var analytics

    var body: some View {
        Button {
            if let trackingScreen {
                analytics.track(.buttonTap(.paste, on: trackingScreen))
            }
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
