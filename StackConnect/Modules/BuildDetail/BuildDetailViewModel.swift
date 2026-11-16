import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol BuildDetailViewModelProtocol: ObservableObject {
    var uiState: BuildDetailUiState { get set }
    func load() async
    func refresh() async
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
    private let analytics: AnalyticsTracking

    init(
        build: BuildModel,
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared
    ) {
        self.uiState = BuildDetailUiState(build: build, appId: appId, account: account)
        self.keychain = keychain
        self.analytics = analytics
    }

    func load() async {
        _ = await performLoad()
    }

    /// Pull-to-refresh: same load, tracked as a `refresh` action with its outcome.
    func refresh() async {
        let succeeded = await performLoad()
        analytics.track(.action(.refresh, on: .buildDetail, result: succeeded ? .success : .failure))
    }

    private func performLoad() async -> Bool {
        var succeeded = true
        uiState.isLoading = true
        uiState.error = nil

        do {
            guard let connection = createConnection() else {
                uiState.isLoading = false
                return false
            }

            let detail = try await connection.fetchBuildDetail(buildId: uiState.build.id)
            uiState.build = detail.build
            uiState.betaGroups = detail.betaGroups
            uiState.localizations = detail.localizations
            Log.print.info("[BuildDetail] Loaded detail for build \(self.uiState.build.id)")
        } catch {
            succeeded = false
            uiState.error = error.localizedDescription
            Log.print.error("[BuildDetail] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        return succeeded
    }

    func expireBuild() async {
        analytics.track(.buttonTap(.confirmExpire, on: .buildDetail))
        uiState.isExpiring = true
        do {
            guard let connection = createConnection() else {
                uiState.isExpiring = false
                analytics.track(.action(.expireBuild, on: .buildDetail, result: .failure))
                return
            }
            try await connection.expireBuild(buildId: uiState.build.id)
            uiState.build.isExpired = true
            uiState.toastMessage = ToastMessage(String(localized: "Build expired"), icon: "clock.badge.xmark")
            analytics.track(.action(.expireBuild, on: .buildDetail, result: .success))
        } catch {
            analytics.track(.action(.expireBuild, on: .buildDetail, result: .failure))
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
