import SwiftUI

// MARK: - Factory

@MainActor
struct SubmissionsViewFactory {
    static func build(
        appId: String,
        appName: String?,
        platform: AppPlatform?,
        account: AccountModel
    ) -> some View {
        SubmissionsEntry(appId: appId, appName: appName, platform: platform, account: account)
    }
}

// MARK: - Entry

private struct SubmissionsEntry: View {
    let appId: String
    let appName: String?
    let platform: AppPlatform?
    let account: AccountModel

    @StateObject private var viewModel: SubmissionsViewModel

    init(appId: String, appName: String?, platform: AppPlatform?, account: AccountModel) {
        self.appId = appId
        self.appName = appName
        self.platform = platform
        self.account = account
        _viewModel = StateObject(
            wrappedValue: SubmissionsViewModel(
                appId: appId,
                appName: appName,
                platform: platform,
                account: account
            )
        )
    }

    var body: some View {
        SubmissionsView(viewModel: viewModel)
    }
}

// MARK: - View

struct SubmissionsView<ViewModel: SubmissionsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    private var account: AccountModel { viewModel.uiState.account }

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Submissions"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert(
                viewModel.uiState.pendingAction?.title ?? "",
                isPresented: Binding(
                    get: { viewModel.uiState.pendingAction != nil },
                    set: { if !$0 { viewModel.uiState.pendingAction = nil } }
                )
            ) {
                if let action = viewModel.uiState.pendingAction {
                    Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                        perform(action)
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {
                        viewModel.uiState.pendingAction = nil
                    }
                }
            } message: {
                if let action = viewModel.uiState.pendingAction {
                    Text(action.message(version: action.submission.versionString))
                }
            }
            .alert(
                String(localized: "Error"),
                isPresented: Binding(
                    get: { viewModel.uiState.error != nil },
                    set: { if !$0 { viewModel.uiState.error = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {
                    viewModel.uiState.error = nil
                }
            } message: {
                if let error = viewModel.uiState.error {
                    Text(error)
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
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
                Label(String(localized: "No Submissions"), systemImage: "paperplane")
            } description: {
                Text("No review submissions found for this app.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            Section {
                SubmissionsLimitBanner(
                    concurrentCount: viewModel.uiState.concurrentCount,
                    concurrentLimit: viewModel.uiState.concurrentLimit,
                    limitReached: viewModel.uiState.limitReached
                )
            } footer: {
                if let appName = viewModel.uiState.appName, !appName.isEmpty {
                    Text(appName)
                }
            }

            Section {
                ForEach(viewModel.uiState.submissions) { submission in
                    buildRow(submission)
                }
            }
        }
    }

    private func buildRow(_ submission: ReviewSubmissionModel) -> some View {
        Button {
            homeCoordinator.navigateToReviewSubmissionDetail(
                submission: submission,
                account: account
            )
        } label: {
            SubmissionRowView(
                submission: submission,
                isBusy: viewModel.uiState.discardingIds.contains(submission.id)
            )
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if account.canDelete(.version) {
                Button(role: .destructive) {
                    viewModel.uiState.pendingAction = .discard(submission)
                } label: {
                    Label(String(localized: "Discard"), systemImage: "trash")
                }
            }

            if submission.state == "READY_FOR_REVIEW" && account.canEdit(.version) {
                Button {
                    viewModel.uiState.pendingAction = .submit(submission)
                } label: {
                    Label(String(localized: "Submit"), systemImage: "paperplane")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Actions

    private func perform(_ action: SubmissionsPendingAction) {
        viewModel.uiState.pendingAction = nil
        switch action {
        case .discard(let submission):
            Task { await viewModel.discard(submission) }
        case .submit(let submission):
            Task { await viewModel.submit(submission) }
        }
    }
}
