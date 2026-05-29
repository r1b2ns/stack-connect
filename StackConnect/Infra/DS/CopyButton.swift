import SwiftUI
import UIKit

/// Compact button that copies a string to the pasteboard, showing a brief
/// checkmark confirmation. Uses `.borderless` so it can sit next to other
/// controls inside a List/Form row without hijacking the row's tap.
struct CopyButton: View {
    let text: String

    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation { copied = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copied ? Color.green : Color.accentColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty)
        .accessibilityLabel(String(localized: "Copy"))
    }
}
