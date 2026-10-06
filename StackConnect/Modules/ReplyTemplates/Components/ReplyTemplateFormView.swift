import SwiftUI

/// Create/edit form for a single reply template.
///
/// Deliberately state-free with respect to persistence: it owns only the draft
/// text and hands it back through `onSubmit`, leaving the ViewModel to decide
/// whether that means a create or an update. Keeps the form reusable for both
/// modes and trivially previewable.
struct ReplyTemplateFormView: View {

    let mode: ReplyTemplateFormMode
    let onSubmit: (String, String) -> Void

    @State private var title: String
    @State private var templateBody: String

    @Environment(\.dismiss) private var dismiss

    init(mode: ReplyTemplateFormMode, onSubmit: @escaping (String, String) -> Void) {
        self.mode = mode
        self.onSubmit = onSubmit
        _title = State(initialValue: mode.template?.title ?? "")
        _templateBody = State(initialValue: mode.template?.body ?? "")
    }

    private var isEditing: Bool { mode.template != nil }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !templateBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Template name"), text: $title)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Only you can see this name. It is never shown on the App Store.")
                }

                Section {
                    TextEditor(text: $templateBody)
                        .frame(minHeight: 150)
                } header: {
                    Text("Message")
                } footer: {
                    Text("This text pre-fills the reply composer. You can edit it before sending.")
                }
            }
            .navigationTitle(isEditing
                ? String(localized: "Edit Template")
                : String(localized: "New Template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        onSubmit(title, templateBody)
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
}
