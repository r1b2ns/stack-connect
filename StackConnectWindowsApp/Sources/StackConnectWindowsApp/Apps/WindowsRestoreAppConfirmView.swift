import SwiftCrossUI
import StackHomeCore
import WindowsAppCore

// T-W07 — Restore confirmation screen pushed as a route (TC-072).
//
// SwiftCrossUI has no `.alert` or `.sheet`, so the restore confirmation is a
// full pushed screen following the same pattern as `WindowsArchiveAppConfirmView`
// (T-W06). The user sees a message and two buttons: Confirm (restores the app
// + pops back) and Cancel (pops back without restoring).
//
// The model reference is passed in so the confirm/cancel intents mutate the
// same `WindowsArchivedAppsModel` instance that owns the archived apps list
// state.

struct WindowsRestoreAppConfirmView: View {

    let appId: String
    /// Display name passed from the route so the confirmation can show it
    /// without a model lookup (the model is still used for confirm/cancel).
    let appName: String
    let model: WindowsArchivedAppsModel
    let coordinator: WindowsHomeCoordinator

    var body: some View {
        VStack(spacing: 16) {
            WindowsBackButtonView(onBack: {
                model.cancelRestore()
                coordinator.pop()
            })

            Spacer()

            // Info icon glyph
            Text("\u{2139}")
                .font(.title)

            Text("Restore App?")
                .font(.title2)
                .fontWeight(.bold)

            Text("Are you sure you want to restore \"\(appName)\"? The app will be moved back to the main Apps list.")
                .foregroundColor(.gray)

            HStack(spacing: 16) {
                Button("Cancel") {
                    model.cancelRestore()
                    coordinator.pop()
                }

                Button("Confirm Restore") {
                    Task {
                        await model.restoreAppConfirmed(appId: appId)
                        coordinator.pop()
                    }
                }
                .foregroundColor(.blue)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: 860)
    }
}
