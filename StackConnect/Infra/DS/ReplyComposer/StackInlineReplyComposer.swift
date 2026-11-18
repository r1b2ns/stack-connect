import SwiftUI

/// The reply composer laid out inline, as List rows under the review (regular
/// width), instead of the `StackReplyComposer` sheet: template chips, the
/// editor, who will see it, the character counter, the last error and the
/// Send / Cancel buttons. ⌘⏎ sends.
///
/// Rows only: place it inside a `Section`.
struct StackInlineReplyComposer: View {

    struct Template: Identifiable, Hashable {
        let id: String
        let title: String
    }

    @Binding var text: String
    let confirmTitle: String
    /// Who will see the reply.
    let footer: String
    var characterLimit: Int?
    var error: String?
    var templates: [Template] = []
    let isSending: Bool
    let canSend: Bool
    let onSelectTemplate: (Template) -> Void
    let onSend: () -> Void
    /// Shown as a Cancel button when set (editing an existing reply).
    var onCancel: (() -> Void)?

    var body: some View {
        if !templates.isEmpty {
            buildTemplateChips()
        }

        TextEditor(text: $text)
            .frame(minHeight: 140)
            .disabled(isSending)
            .accessibilityLabel(String(localized: "Your Reply"))

        VStack(alignment: .leading, spacing: 4) {
            Text(footer)
            if let characterLimit {
                StackReplyCharacterCounter(count: text.count, limit: characterLimit)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)

        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }

        buildButtons()
    }

    private func buildTemplateChips() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(templates) { template in
                    Button {
                        onSelectTemplate(template)
                    } label: {
                        Text(template.title)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(isSending)
    }

    private func buildButtons() -> some View {
        HStack {
            if let onCancel {
                Button(String(localized: "Cancel"), role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .disabled(isSending)
            }

            Spacer()

            if isSending {
                ProgressView()
            }

            Button {
                onSend()
            } label: {
                Text(confirmTitle)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help(String(localized: "Send (⌘↩)", comment: "Tooltip of the inline reply composer's send button."))
        }
    }
}
