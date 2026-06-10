import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// T-W24 — Reply Composer screen for the Windows GUI.
//
// Displays a multiline text editor for composing or editing a developer
// response to a customer review. Supports both create (nil existingReplyBody)
// and edit (pre-populated) flows via the
// `.replyComposer(reviewId:accountId:existingReplyBody:)` route.
//
// Features:
// - Multiline TextEditor with label/placeholder fallback (R6).
// - Submit button disabled when empty or pending (AC-W13-1).
// - Loading indicator + disabled input while isPending (AC-W13-2).
// - On success, pops back to Review Detail (TC-034/036; AC-W13-3).
// - On failure, stays open with error message for retry (TC-043; AC-W13-4).
// - Dirty-state guard: inline "Discard / Keep editing" when user tries to
//   leave with unsaved changes (SwiftCrossUI constraint: no sheets/alerts).
//
// Follows the Factory + direct-init pattern used by `WindowsReviewDetailView`
// (T-W23): no Entry/StateObject layer because SwiftCrossUI uses `@State` (not
// `@StateObject`) and the model is created externally by RootView.

// MARK: - Factory

/// Factory for the Reply Composer screen. Creates the model and view, matching
/// the Factory pattern used by `WindowsReviewDetailView` (T-W23).
@MainActor
enum WindowsReplyComposerViewFactory {

    /// Builds the Reply Composer screen.
    ///
    /// - Parameters:
    ///   - reviewId: The customer review identifier.
    ///   - accountId: The owning account identifier.
    ///   - existingReplyBody: The existing reply body (nil for create mode).
    ///   - coordinator: The navigation coordinator.
    ///   - model: The reply composer model (created by RootView).
    static func build(
        reviewId: String,
        accountId: String,
        existingReplyBody: String?,
        coordinator: WindowsHomeCoordinator,
        model: WindowsReplyComposerModel
    ) -> WindowsReplyComposerView {
        WindowsReplyComposerView(
            reviewId: reviewId,
            accountId: accountId,
            existingReplyBody: existingReplyBody,
            coordinator: coordinator,
            model: model
        )
    }
}

// MARK: - View

struct WindowsReplyComposerView: View {

    /// The customer review identifier.
    let reviewId: String
    /// The owning account identifier.
    let accountId: String
    /// The existing reply body (nil for create mode, non-nil for edit).
    let existingReplyBody: String?
    /// Navigation coordinator -- Back pops, success pops.
    @State private var coordinator: WindowsHomeCoordinator
    /// The reply composer model. Observed via `@State` so the view redraws
    /// when the model's `@Published` properties change.
    @State private var model: WindowsReplyComposerModel

    /// Whether the inline discard confirmation is showing.
    @State private var showDiscardConfirmation: Bool = false

    /// Managed task for the submit operation. Storing the handle prevents
    /// fire-and-forget leaks and allows cancellation if the view disappears
    /// or the user navigates away. Matches the managed-Task pattern from
    /// sibling views (SHOULD-FIX #4).
    @State private var submitTask: Task<Void, Never>?

    init(
        reviewId: String,
        accountId: String,
        existingReplyBody: String?,
        coordinator: WindowsHomeCoordinator,
        model: WindowsReplyComposerModel
    ) {
        self.reviewId = reviewId
        self.accountId = accountId
        self.existingReplyBody = existingReplyBody
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                buildToolbar()
                buildDiscardConfirmation()
                buildErrorBanner()
                buildEditorSection()
                buildSubmitSection()
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
        .onChange(of: model.didSucceed) {
            // TC-034/036: On success, pop back to review detail.
            if model.didSucceed {
                coordinator.pop()
            }
        }
    }

    // MARK: - Toolbar (back + title)

    /// Header: shared "< Back" component on the left, title below.
    /// Back triggers dirty guard if editor has unsaved changes.
    @ViewBuilder
    private func buildToolbar() -> some View {
        VStack(spacing: 12) {
            WindowsBackButtonView(onBack: { handleBack() })
            HStack {
                Text(existingReplyBody != nil ? "Edit Reply" : "Write a Reply")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Discard Confirmation (dirty guard)

    /// Inline discard confirmation shown when the user tries to leave with
    /// unsaved changes. Uses inline buttons instead of alerts/sheets
    /// (SwiftCrossUI constraint).
    @ViewBuilder
    private func buildDiscardConfirmation() -> some View {
        if showDiscardConfirmation {
            VStack(spacing: 12) {
                HStack {
                    Text("You have unsaved changes. Discard them?")
                        .foregroundColor(.orange)
                    Spacer()
                }
                HStack(spacing: 12) {
                    Button("Discard") {
                        showDiscardConfirmation = false
                        coordinator.pop()
                    }
                    .foregroundColor(.red)

                    Button("Keep Editing") {
                        showDiscardConfirmation = false
                    }

                    Spacer()
                }
            }
            .padding(12)
            .background(Color(white: 0.94))
            .cornerRadius(8)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.5), style: StrokeStyle(width: 1.0))
            }
        }
    }

    // MARK: - Error Banner (AC-W13-4, TC-043)

    /// Non-blocking error banner shown when a submit fails. The composer stays
    /// open for retry.
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

    // MARK: - Editor Section

    /// Multiline text editor with a label. SwiftCrossUI does not support a
    /// native placeholder on TextEditor, so a label above the editor serves
    /// as the placeholder fallback (risk R6).
    @ViewBuilder
    private func buildEditorSection() -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Your response:")
                    .foregroundColor(.gray)
                Spacer()
            }

            TextEditor(text: $model.text)
                .frame(minHeight: 160)
                .disabled(model.isPending)
        }
        .padding(16)
        .background(Color(white: 0.97))
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(width: 1.0))
        }
    }

    // MARK: - Submit Section

    /// Submit button with loading indicator. Disabled when empty or pending
    /// (AC-W13-1/2). The Task is stored in `submitTask` so it can be cancelled
    /// and does not leak (SHOULD-FIX #4).
    @ViewBuilder
    private func buildSubmitSection() -> some View {
        HStack(spacing: 12) {
            Button("Submit") {
                submitTask?.cancel()
                submitTask = Task {
                    await model.submitReply(responseBody: model.text)
                }
            }
            .disabled(!model.canSubmit)

            if model.isPending {
                ProgressView()
                Text("Submitting...")
                    .foregroundColor(.gray)
            }

            Spacer()
        }
    }

    // MARK: - Back Navigation with Dirty Guard

    /// Handles the back action. If the editor has unsaved changes (dirty),
    /// shows the inline discard confirmation instead of navigating immediately.
    private func handleBack() {
        if model.isDirty {
            showDiscardConfirmation = true
        } else {
            coordinator.pop()
        }
    }
}
