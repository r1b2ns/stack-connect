import SwiftUI

/// Review Checklist (prototype screen 6): the release items Google will
/// validate, "Send changes for review", "If a review is in progress", and —
/// when Google refuses the edit — its message with Share Error. Publishing
/// here is the write's confirmation (plan R4, said in the footer).
///
/// Shown as its own sheet (Release to All Users, Save on the release detail)
/// or pushed inside the Staged Rollout and New Release sheets.
struct GooglePlayReviewChecklistView<Writes: GooglePlayReleaseWriteViewModelProtocol>: View {

    let write: GooglePlayPendingWrite
    @ObservedObject var writes: Writes
    /// Root of its own sheet: shows Cancel (pushed, the back button does).
    let isRoot: Bool

    private var checklist: GooglePlayReviewChecklist { writes.checklist(for: write) }

    var body: some View {
        Form {
            Section {
                ForEach(checklist.items) { item in
                    StackChecklistRow(
                        title: item.title,
                        detail: item.detail,
                        value: item.value,
                        isSatisfied: item.state == .satisfied
                    )
                }
            } header: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Review the changes below before sending them to Google Play.")
                        .textCase(nil)
                        .font(.subheadline)
                    Text(checklist.title)
                }
            }

            Section {
                Toggle(isOn: $writes.uiState.commitOptions.sendForReview) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send changes for review")
                        Text("Off keeps them in Play Console until you send them there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Picker(String(localized: "If a review is in progress"), selection: $writes.uiState.commitOptions.reviewInProgress) {
                    ForEach(GooglePlayCommitOptions.ReviewInProgressBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
            } header: {
                Text("Google Play Review")
            } footer: {
                Text(writes.uiState.checklistEditFooter)
            }

            if let error = writes.uiState.checklistError {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(String(localized: "Validation failed"), systemImage: "exclamationmark.octagon.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                    StackErrorShareLink(message: error, context: writes.errorContext)
                }
            }
        }
        .navigationTitle(String(localized: "Review Checklist"))
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(.googlePlayReviewChecklist)
        .disabled(writes.uiState.isWriting)
        .overlay {
            if writes.uiState.isWriting {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) {
                    StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayReviewChecklist) { writes.cancelPendingWrite() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                // The commit and its outcome are tracked by `confirm`.
                StackTrackedButton(String(localized: "Publish"), button: .publish, on: .googlePlayReviewChecklist) {
                    Task { await writes.confirm(write) }
                }
                .fontWeight(.semibold)
                .disabled(writes.uiState.isWriting)
            }
        }
        .task { await writes.loadContext() }
    }
}
