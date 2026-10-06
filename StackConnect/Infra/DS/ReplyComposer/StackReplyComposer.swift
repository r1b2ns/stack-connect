import SwiftUI

/// Reply composer sheet: optional context sections (e.g. the review being
/// answered), a text editor with a footer note and an optional character
/// counter, an inline error, and Cancel / confirm toolbar buttons.
///
/// Used by the review list's swipe-to-reply sheet and the review detail, for
/// every store. The counter is a soft limit: it warns past `characterLimit`
/// but never blocks sending — the store has the final word.
struct StackReplyComposer<Context: View>: View {

    let title: String
    let confirmTitle: String
    @Binding var text: String
    /// Who will see the reply, shown under the editor.
    let footer: String
    var characterLimit: Int? = nil
    /// Last send failure, shown below the editor.
    var error: String? = nil
    var editorMinHeight: CGFloat = 150
    let isSending: Bool
    let onSend: (String) -> Void
    let onCancel: () -> Void
    @ViewBuilder var context: () -> Context

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                context()

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: editorMinHeight)
                } header: {
                    Text("Your Reply")
                } footer: {
                    buildFooter()
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .disabled(isSending)
        }
        // A reply in flight can't be swiped away: its result lands here.
        .interactiveDismissDisabled(isSending)
    }

    // MARK: - Footer

    @ViewBuilder
    private func buildFooter() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(footer)

            if let characterLimit {
                buildCounter(limit: characterLimit)
            }
        }
    }

    private func buildCounter(limit: Int) -> some View {
        let count = text.count
        let isOverLimit = count > limit
        return HStack(spacing: 6) {
            Text(verbatim: "\(count)/\(limit)")
                .monospacedDigit()
            if isOverLimit {
                Text("Longer replies may be rejected.")
            }
        }
        .foregroundStyle(isOverLimit ? Color.orange : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(count) of \(limit) characters"))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel")) {
                dismiss()
                onCancel()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSending {
                ProgressView()
            } else {
                Button(confirmTitle) {
                    onSend(text)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

extension StackReplyComposer where Context == EmptyView {

    /// A composer without context sections.
    init(
        title: String,
        confirmTitle: String,
        text: Binding<String>,
        footer: String,
        characterLimit: Int? = nil,
        error: String? = nil,
        editorMinHeight: CGFloat = 150,
        isSending: Bool,
        onSend: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            title: title,
            confirmTitle: confirmTitle,
            text: text,
            footer: footer,
            characterLimit: characterLimit,
            error: error,
            editorMinHeight: editorMinHeight,
            isSending: isSending,
            onSend: onSend,
            onCancel: onCancel,
            context: { EmptyView() }
        )
    }
}
