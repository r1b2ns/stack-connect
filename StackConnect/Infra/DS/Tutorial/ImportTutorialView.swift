import SwiftUI

/// Presented sheet that explains the end-to-end `.scexport` import flow.
///
/// Hosts ``TutorialGuideView`` inside a `Form` (the component renders a
/// `Section`/`DisclosureGroup` and must live in a `Form`/`List`). The toolbar
/// adds a single combined-text `ShareLink` on top of the per-block shares the
/// guide already provides, plus a Done button that dismisses the sheet.
struct ImportTutorialView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TutorialGuideView(
                    label: String(localized: "How to import?"),
                    systemImage: "questionmark.circle",
                    blocks: ImportTutorial.blocks,
                    caption: String(localized: "Use the share button to send these steps to whoever is importing the account.")
                )
            }
            .navigationTitle(String(localized: "How to import?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: ImportTutorial.fullShareText) {
                        Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
