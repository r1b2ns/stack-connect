import SwiftUI

/// Read-only pre-submit summary shown before a version is sent to App Store
/// review (when the "Check list pre review" setting is ON). Reports the state of
/// each item the reviewer will see; the actual blocking validation happens
/// before this sheet is presented, so by the time it appears every required item
/// is already satisfied. `onSubmit` performs the submission; `onCancel` dismisses.
struct PreSubmitChecklistSheet: View {

    let checklist: PreSubmitChecklist
    let isSubmitting: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    buildValueRow(
                        title: String(localized: "Build selected"),
                        value: checklist.buildNumber ?? String(localized: "None"),
                        satisfied: checklist.hasBuild
                    )
                    buildStatusRow(
                        title: String(localized: "What's New"),
                        satisfied: checklist.whatsNewFilled
                    )
                    buildValueRow(
                        title: String(localized: "Version"),
                        value: checklist.marketingVersion ?? "–",
                        satisfied: true,
                        showsIndicator: false
                    )
                    buildStatusRow(
                        title: String(localized: "Demo account"),
                        satisfied: checklist.demoAccountSatisfied,
                        detail: checklist.isDemoAccountRequired ? nil : String(localized: "Not required")
                    )
                    buildStatusRow(
                        title: String(localized: "Screenshots"),
                        satisfied: checklist.hasScreenshots
                    )
                    buildValueRow(
                        title: String(localized: "App Store release"),
                        value: releaseTypeLabel,
                        satisfied: true,
                        showsIndicator: false
                    )
                    buildValueRow(
                        title: String(localized: "Phased release"),
                        value: checklist.phasedReleaseEnabled
                            ? String(localized: "Enabled")
                            : String(localized: "Disabled"),
                        satisfied: true,
                        showsIndicator: false
                    )
                } header: {
                    Text(String(localized: "Review the details below before submitting to Apple."))
                        .textCase(nil)
                }
            }
            .navigationTitle(String(localized: "Review Checklist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Submit")) { onSubmit() }
                        .fontWeight(.semibold)
                }
            }
            .disabled(isSubmitting)
            .overlay {
                if isSubmitting {
                    ProgressView()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var releaseTypeLabel: String {
        switch checklist.releaseType {
        case .manual:        return String(localized: "Manual")
        case .afterApproval: return String(localized: "Automatic")
        case .scheduled:     return String(localized: "Scheduled")
        }
    }

    // MARK: - Rows

    /// A row showing a label + value, optionally trailed by a status indicator.
    private func buildValueRow(
        title: String,
        value: String,
        satisfied: Bool,
        showsIndicator: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            if showsIndicator {
                statusIcon(satisfied: satisfied)
            }
        }
    }

    /// A row showing a label + a ✅/⚠️ status (with optional detail text).
    private func buildStatusRow(
        title: String,
        satisfied: Bool,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            statusIcon(satisfied: satisfied)
        }
    }

    private func statusIcon(satisfied: Bool) -> some View {
        Image(systemName: satisfied ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(satisfied ? .green : .orange)
    }
}
