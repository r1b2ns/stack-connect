import SwiftUI

struct StackTextView: View {

    let title: String
    @Binding var text: String
    let onSave: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .font(.body)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .disabled(isSaving)
        }
    }

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel")) {
                dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button(String(localized: "Save")) {
                    Task {
                        isSaving = true
                        errorMessage = nil
                        do {
                            try await onSave()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isSaving = false
                    }
                }
            }
        }
    }
}
