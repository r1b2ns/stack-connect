import SwiftUI

// MARK: - Factory

@MainActor
struct AppReviewListViewFactory {
    static func build(appId: String, appName: String, account: AccountModel) -> some View {
        AppReviewListEntry(appId: appId, appName: appName, account: account)
    }
}

// MARK: - Entry

private struct AppReviewListEntry: View {
    let appId: String
    let appName: String
    let account: AccountModel

    @StateObject private var viewModel: AppReviewListViewModel

    init(appId: String, appName: String, account: AccountModel) {
        self.appId = appId
        self.appName = appName
        self.account = account
        _viewModel = StateObject(wrappedValue: AppReviewListViewModel(appId: appId, appName: appName, account: account))
    }

    var body: some View {
        AppReviewListView(viewModel: viewModel)
    }
}

// MARK: - View

struct AppReviewListView<ViewModel: AppReviewListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "App Review"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.loadSubmissions() }
            .refreshable { await viewModel.loadSubmissions() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.submissions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.submissions.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Submissions"), systemImage: "checkmark.shield")
            } description: {
                Text("No review submissions found for this app.")
            }
        }
    }

    private func buildList() -> some View {
        List(viewModel.uiState.submissions) { submission in
            Button {
                homeCoordinator.navigateToReviewSubmissionDetail(
                    submission: submission,
                    account: viewModel.uiState.account
                )
            } label: {
                buildSubmissionRow(submission)
            }
            .foregroundStyle(.primary)
        }
    }

    private func buildSubmissionRow(_ submission: ReviewSubmissionModel) -> some View {
        HStack(spacing: 12) {
            buildStateIndicator(submission)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(submission.versionString ?? "–")
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

                buildStateBadge(submission)
            }
        }
        .padding(.vertical, 2)
    }

    private func buildStateIndicator(_ submission: ReviewSubmissionModel) -> some View {
        Circle()
            .fill(stateColor(submission.stateColor))
            .frame(width: 10, height: 10)
    }

    private func buildStateBadge(_ submission: ReviewSubmissionModel) -> some View {
        HStack(spacing: 6) {
            Text(submission.stateDisplayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(stateColor(submission.stateColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(stateColor(submission.stateColor).opacity(0.12))
                .clipShape(Capsule())

            if let platform = submission.platform {
                Text(submission.platformDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                    .accessibilityHidden(platform.isEmpty)
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
