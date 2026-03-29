import Foundation

// MARK: - Protocol

@MainActor
protocol AppReviewDetailViewModelProtocol: ObservableObject {
    var uiState: AppReviewDetailUiState { get set }
    func loadDetail() async
}

// MARK: - UiState

struct AppReviewDetailUiState {
    var submission: ReviewSubmissionModel
    var account: AccountModel
    var reviewDetail: AppReviewDetailModel?
    var isLoading = false
    var error: String?
}

// MARK: - Implementation

@MainActor
final class AppReviewDetailViewModel: AppReviewDetailViewModelProtocol {

    @Published var uiState: AppReviewDetailUiState

    private let keychain: KeyStorable

    init(
        submission: ReviewSubmissionModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppReviewDetailUiState(submission: submission, account: account)
        self.keychain = keychain
    }

    func loadDetail() async {
        guard let versionId = uiState.submission.versionId else { return }

        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isLoading = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            uiState.reviewDetail = try await connection.fetchAppReviewDetail(versionId: versionId)
            Log.print.info("[AppReviewDetail] Loaded review detail for version \(versionId)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppReviewDetail] Failed to load review detail: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }
}
