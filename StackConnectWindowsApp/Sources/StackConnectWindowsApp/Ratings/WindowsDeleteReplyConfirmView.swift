import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// T-W25 — Delete Reply Confirmation screen for the Windows GUI.
//
// Pushed as a route (.deleteReplyConfirm) when the user taps "Delete Reply" on
// the Review Detail screen. Presents a warning message and two buttons:
// - "Delete" confirms the deletion via the model's `deleteReplyConfirmed()`.
// - "Cancel" pops back without deleting.
//
// On success (model.didSucceed), pops back to the Review Detail. On failure,
// stays open with an inline error banner for retry (AC-W13-9).
//
// Follows the Factory + direct-init pattern used by `WindowsReplyComposerView`
// (T-W24) and the confirmation screen structure of
// `WindowsArchiveAppConfirmView` / `WindowsRestoreAppConfirmView`.

// MARK: - Factory

/// Factory for the Delete Reply Confirm screen. Matches the Factory pattern
/// used by `WindowsReplyComposerView` (T-W24) for parity.
@MainActor
enum WindowsDeleteReplyConfirmViewFactory {

    /// Builds the Delete Reply Confirm screen.
    ///
    /// - Parameters:
    ///   - reviewId: The customer review identifier.
    ///   - responseId: The response identifier to delete.
    ///   - accountId: The owning account identifier.
    ///   - coordinator: The navigation coordinator.
    ///   - model: The delete reply confirm model (created by RootView).
    static func build(
        reviewId: String,
        responseId: String,
        accountId: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsDeleteReplyConfirmModel
    ) -> WindowsDeleteReplyConfirmView {
        WindowsDeleteReplyConfirmView(
            reviewId: reviewId,
            responseId: responseId,
            accountId: accountId,
            coordinator: coordinator,
            model: model
        )
    }
}

// MARK: - View

struct WindowsDeleteReplyConfirmView: View {

    /// The customer review identifier.
    let reviewId: String
    /// The response identifier to delete.
    let responseId: String
    /// The owning account identifier.
    let accountId: String
    /// Navigation coordinator -- Back/Cancel pops, success pops.
    @State private var coordinator: WindowsHomeCoordinator
    /// The delete reply confirm model. Observed via `@State` so the view
    /// redraws when the model's `@Published` properties change.
    @State private var model: WindowsDeleteReplyConfirmModel

    /// Managed task for the delete operation. Storing the handle prevents
    /// fire-and-forget leaks and allows cancellation if the view disappears
    /// or the user navigates away.
    @State private var deleteTask: Task<Void, Never>?

    init(
        reviewId: String,
        responseId: String,
        accountId: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsDeleteReplyConfirmModel
    ) {
        self.reviewId = reviewId
        self.responseId = responseId
        self.accountId = accountId
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                buildToolbar()
                buildErrorBanner()
                buildConfirmationContent()
                buildActionButtons()
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
        .onChange(of: model.didSucceed) {
            // AC-W13-8: On success, pop back to review detail.
            if model.didSucceed {
                coordinator.pop()
            }
        }
    }

    // MARK: - Toolbar (back + title)

    /// Header: shared "< Back" component on the left, title below.
    @ViewBuilder
    private func buildToolbar() -> some View {
        VStack(spacing: 12) {
            WindowsBackButtonView(onBack: {
                deleteTask?.cancel()
                coordinator.pop()
            })
            HStack {
                Text("Delete Reply")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Error Banner (AC-W13-9)

    /// Non-blocking error banner shown when a delete fails. The confirmation
    /// screen stays open for retry.
    @ViewBuilder
    private func buildErrorBanner() -> some View {
        if let errorMessage = model.error {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(errorMessage)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(12)
            }
            .background(Color(white: 0.94))
            .cornerRadius(8)
        }
    }

    // MARK: - Confirmation Content

    /// Warning icon and confirmation message (TC-037 step 6).
    @ViewBuilder
    private func buildConfirmationContent() -> some View {
        VStack(spacing: 12) {
            Spacer()

            // Warning icon glyph
            Text("\u{26A0}")
                .font(.title)

            Text("Delete Reply?")
                .font(.title2)
                .fontWeight(.bold)

            Text("Are you sure you want to delete this reply?")
                .foregroundColor(.gray)

            Spacer()
        }
    }

    // MARK: - Action Buttons

    /// Delete (confirm) and Cancel buttons with pending indicator.
    @ViewBuilder
    private func buildActionButtons() -> some View {
        HStack(spacing: 16) {
            Button("Cancel") {
                deleteTask?.cancel()
                coordinator.pop()
            }

            Button("Delete") {
                deleteTask?.cancel()
                deleteTask = Task {
                    await model.deleteReplyConfirmed()
                }
            }
            .disabled(model.isPending)
            .foregroundColor(.red)

            if model.isPending {
                ProgressView()
                Text("Deleting...")
                    .foregroundColor(.gray)
            }

            Spacer()
        }
    }
}
