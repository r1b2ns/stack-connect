import SwiftCrossUI
import StackHomeCore
import WindowsAppCore

// T-W12 — Archive confirmation screen for the App Detail flow.
//
// Mirrors `WindowsArchiveAppConfirmView` (T-W06) but operates on a
// `WindowsAppDetailModel` instead of `WindowsAppsListModel`. The user sees a
// warning message and two buttons: Confirm (archives the app via the detail
// model + pops back to the apps list) and Cancel (pops back to the detail
// without archiving).
//
// The model reference is passed in so the confirm/cancel intents mutate the
// same `WindowsAppDetailModel` instance that owns the detail state. On
// confirm, the coordinator pops twice (past the confirmation AND the detail
// screen) returning to the apps list (AC-W09-3 / TC-021).
//
// This uses a PUSHED ROUTE (TC-072), not an alert/sheet, consistent with the
// other confirmation screens in the Windows port.

struct WindowsArchiveAppDetailConfirmView: View {

    let appId: String
    /// Display name passed from the route so the confirmation can show it
    /// without a model lookup (the model is still used for confirm).
    let appName: String
    let accountId: String
    let model: WindowsAppDetailModel
    let coordinator: WindowsHomeCoordinator
    /// Called after a confirmed archive to invalidate the cached detail model
    /// so the freed model is not retained across future navigations (SF-2).
    let onArchiveConfirmed: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            WindowsBackButtonView(onBack: {
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
                    coordinator.pop()
                }

                Button("Confirm Archive") {
                    Task {
                        await model.archiveApp(appId: appId, accountId: accountId)
                        onArchiveConfirmed()
                        // Pop twice: past the confirmation AND the detail screen,
                        // returning to the apps list (AC-W09-3 / TC-021).
                        coordinator.pop()
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
