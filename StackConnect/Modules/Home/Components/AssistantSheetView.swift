import SwiftUI
import AppIntents

struct AssistantSheetView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String(localized: "Use Siri or tap an action below to manage your apps with voice commands."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "Available Actions")) {
                    releaseRow
                    rejectRow
                }

                Section(String(localized: "Siri Phrases")) {
                    SiriTipView(intent: ReleaseVersionIntent())
                    SiriTipView(intent: RejectVersionIntent())
                }
            }
            .navigationTitle(String(localized: "Assistant"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private var releaseRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Release Version"))
                    .font(.body.weight(.medium))
                Text(String(localized: "Release an app pending developer release"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rejectRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Reject Version"))
                    .font(.body.weight(.medium))
                Text(String(localized: "Reject an app pending developer release"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
