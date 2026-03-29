import Foundation

// MARK: - Protocol

@MainActor
protocol AppReviewListViewModelProtocol: ObservableObject {
    var uiState: AppReviewListUiState { get set }
    func loadSubmissions() async
}

// MARK: - UiState

struct AppReviewListUiState {
    var appId: String
    var appName: String
    var account: AccountModel
    var submissions: [ReviewSubmissionModel] = []
    var isLoading = false
    var error: String?
}

// MARK: - Implementation

@MainActor
final class AppReviewListViewModel: AppReviewListViewModelProtocol {

    @Published var uiState: AppReviewListUiState

    private let keychain: KeyStorable

    init(
        appId: String,
        appName: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppReviewListUiState(appId: appId, appName: appName, account: account)
        self.keychain = keychain
    }

    func loadSubmissions() async {
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
                uiState.isLoading = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            uiState.submissions = try await connection.fetchReviewSubmissions(appId: uiState.appId)
            Log.print.info("[AppReview] Loaded \(self.uiState.submissions.count) submissions for \(self.uiState.appName)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AppReview] Failed to load submissions: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }
}
