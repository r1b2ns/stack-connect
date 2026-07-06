import SwiftUI

/// A single review-submission row. Mirrors the row from the (retired) App Review
/// list: a leading state dot, a title, a submitter/date subtitle and a trailing
/// state badge, plus a distinct "Draft" badge for unfinished submissions.
struct SubmissionRowView: View {

    let submission: ReviewSubmissionModel
    /// When true, shows a trailing spinner (an action is in flight for this row).
    var isBusy: Bool = false

    private var isDraft: Bool {
        submission.state == "READY_FOR_REVIEW"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(stateColor(submission.stateColor))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)

                    Spacer()

                    Text(formatDate(submission.submittedDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let name = submission.submittedByName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                buildBadges()
            }

            if isBusy {
                ProgressView()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Title

    /// Drafts frequently have no `versionString`, so fall back to a
    /// platform-qualified generic label.
    private var title: String {
        if let version = submission.versionString, !version.isEmpty {
            return version
        }
        if submission.platform != nil {
            return String(localized: "\(submission.platformDisplayName) Submission")
        }
        return String(localized: "iOS Submission")
    }

    // MARK: - Badges

    @ViewBuilder
    private func buildBadges() -> some View {
        HStack(spacing: 6) {
            if isDraft {
                Text(String(localized: "Draft"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Text(submission.stateDisplayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(stateColor(submission.stateColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor(submission.stateColor).opacity(0.12))
                    .clipShape(Capsule())
            }

            if submission.platform != nil {
                Text(submission.platformDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "–" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM, EEE, HH:mm"
        return formatter.string(from: date)
    }

    private func stateColor(_ color: AppStoreStateColor) -> Color {
        switch color {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}
