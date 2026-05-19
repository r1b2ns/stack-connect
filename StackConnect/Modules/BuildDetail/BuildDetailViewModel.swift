import Foundation

// MARK: - Protocol

@MainActor
protocol BuildDetailViewModelProtocol: ObservableObject {
    var uiState: BuildDetailUiState { get set }
    func load() async
    func expireBuild() async
}

// MARK: - UiState

struct BuildDetailUiState {
    var build: BuildModel
    var appId: String
    var account: AccountModel
    var betaGroups: [BetaGroupModel] = []
    var localizations: [BetaBuildLocalizationModel] = []
    var isLoading = false
    var isExpiring = false
    var showExpireConfirm = false
    var toastMessage: ToastMessage?
    var error: String?
}

// MARK: - Implementation

@MainActor
final class BuildDetailViewModel: BuildDetailViewModelProtocol {

    @Published var uiState: BuildDetailUiState

    private let keychain: KeyStorable

    init(build: BuildModel, appId: String, account: AccountModel, keychain: KeyStorable = KeychainStorable.shared) {
        self.uiState = BuildDetailUiState(build: build, appId: appId, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let connection = createConnection() else {
                uiState.isLoading = false
                return
            }

            let detail = try await connection.fetchBuildDetail(buildId: uiState.build.id)
            uiState.build = detail.build
            uiState.betaGroups = detail.betaGroups
            uiState.localizations = detail.localizations
            Log.print.info("[BuildDetail] Loaded detail for build \(self.uiState.build.id)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[BuildDetail] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func expireBuild() async {
        uiState.isExpiring = true
        do {
            guard let connection = createConnection() else {
                uiState.isExpiring = false
                return
            }
            try await connection.expireBuild(buildId: uiState.build.id)
            uiState.build.isExpired = true
            uiState.toastMessage = ToastMessage(String(localized: "Build expired"), icon: "clock.badge.xmark")
        } catch {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to expire build"), icon: "exclamationmark.triangle.fill")
            Log.print.error("[BuildDetail] Expire failed: \(error.localizedDescription)")
        }
        uiState.isExpiring = false
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        return AppleAccountConnection(credentials: credentials)
    }
}
