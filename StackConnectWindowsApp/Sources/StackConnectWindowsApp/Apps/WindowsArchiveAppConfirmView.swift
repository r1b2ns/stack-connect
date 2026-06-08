import SwiftCrossUI
import StackHomeCore
import WindowsAppCore

// T-W06 — Archive confirmation screen pushed as a route (TC-072).
//
// SwiftCrossUI has no `.alert` or `.sheet`, so the archive confirmation is a
// full pushed screen following the `deleteReplyConfirm`-style pattern from
// T-W03. The user sees a warning message and two buttons: Confirm (archives
// the app + pops back) and Cancel (pops back without archiving).
//
// The model reference is passed in so the confirm/cancel intents mutate the
// same `WindowsAppsListModel` instance that owns the apps list state.

struct WindowsArchiveAppConfirmView: View {

    let appId: String
    /// Display name passed from the route so the confirmation can show it
    /// without a model lookup (the model is still used for confirm/cancel).
    let appName: String
    let model: WindowsAppsListModel
    let coordinator: WindowsHomeCoordinator

    var body: some View {
        VStack(spacing: 16) {
            WindowsBackButtonView(onBack: {
                model.cancelArchive()
                coordinator.pop()
            })

            Spacer()

            // Warning icon glyph
            Text("\u{26A0}")
                .font(.title)

            Text("Archive App?")
                .font(.title2)
                .fontWeight(.bold)

            Text("Are you sure you want to archive \"\(appName)\"? Archived apps will be moved to the Archived list.")
                .foregroundColor(.gray)

            HStack(spacing: 16) {
                Button("Cancel") {
                    model.cancelArchive()
                    coordinator.pop()
                }

                Button("Confirm Archive") {
                    Task {
                        await model.archiveAppConfirmed(appId: appId)
                        coordinator.pop()
                    }
                }
                .foregroundColor(.orange)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: 860)
    }
}
