import SwiftUI

// MARK: - Factory

@MainActor
struct SubmissionsViewFactory {
    static func build(
        appId: String,
        appName: String?,
        account: AccountModel
    ) -> some View {
        SubmissionsEntry(appId: appId, appName: appName, account: account)
    }
}

// MARK: - Entry

private struct SubmissionsEntry: View {
    let appId: String
    let appName: String?
    let account: AccountModel

    @StateObject private var viewModel: SubmissionsViewModel

    init(appId: String, appName: String?, account: AccountModel) {
        self.appId = appId
        self.appName = appName
        self.account = account
        _viewModel = StateObject(
            wrappedValue: SubmissionsViewModel(
                appId: appId,
                appName: appName,
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
    @Environment(\.openURL) private var openURL

    private var account: AccountModel { viewModel.uiState.account }

    /// App Store Connect distribution page for this app — where the user can
    /// remove a stuck review submission that the public API can't delete.
    private var appStoreConnectDistributionURL: URL? {
        URL(string: "https://appstoreconnect.apple.com/apps/\(viewModel.uiState.appId)/distribution")
    }

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Submissions"))
            .trackScreen(.submissions)
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .refreshable { await viewModel.refresh() }
            .alert(
                viewModel.uiState.pendingAction?.title ?? "",
                isPresented: Binding(
                    get: { viewModel.uiState.pendingAction != nil },
                    set: { if !$0 { viewModel.uiState.pendingAction = nil } }
                )
            ) {
                if let action = viewModel.uiState.pendingAction {
                    StackTrackedButton(action.confirmLabel, button: action.analyticsConfirmButton, on: .submissions, role: action.isDestructive ? .destructive : nil) {
                        perform(action)
                    }
                    StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .submissions, role: .cancel) {
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
                StackTrackedButton(String(localized: "OK"), button: .ok, on: .submissions, role: .cancel) {
                    viewModel.uiState.error = nil
                }
            } message: {
                if let error = viewModel.uiState.error {
                    Text(error)
                }
            }
            .alert(
                String(localized: "Can't remove via API"),
                isPresented: Binding(
                    get: { viewModel.uiState.notRemovable != nil },
                    set: { if !$0 { viewModel.uiState.notRemovable = nil } }
                )
            ) {
                if let url = appStoreConnectDistributionURL {
                    StackTrackedButton(String(localized: "Open App Store Connect"), button: .openAppStoreConnect, on: .submissions) {
                        openURL(url)
                        viewModel.uiState.notRemovable = nil
                    }
                }
                StackTrackedButton(String(localized: "Close"), button: .close, on: .submissions, role: .cancel) {
                    viewModel.uiState.notRemovable = nil
                }
            } message: {
                if let message = viewModel.uiState.notRemovable {
                    Text(message)
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
            .featureOnboarding(.submissions)
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
                Text(String(localized: "No review submissions found for this app."))
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
        StackTrackedButton(.submission, on: .submissions) {
            homeCoordinator.navigateToReviewSubmissionDetail(
                submission: submission,
                account: account
            )
        } label: {
            SubmissionRowView(
                submission: submission,
                isBusy: viewModel.uiState.busyIds.contains(submission.id)
            )
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if account.canDelete(.version) {
                StackTrackedButton(.discard, on: .submissions, role: .destructive) {
                    viewModel.uiState.pendingAction = .discard(submission)
                } label: {
                    Label(String(localized: "Discard"), systemImage: "trash")
                }
            }

            if submission.state == "READY_FOR_REVIEW" && account.canEdit(.version) {
                StackTrackedButton(.submitForReview, on: .submissions) {
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

// MARK: - Analytics

private extension SubmissionsPendingAction {
    /// The confirm button of this action's alert.
    var analyticsConfirmButton: AnalyticsButton {
        switch self {
        case .discard: return .confirmDiscard
        case .submit: return .confirmSubmit
        }
    }
}
