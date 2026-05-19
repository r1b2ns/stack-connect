import Foundation

// MARK: - Protocol

@MainActor
protocol PlatformBuildsViewModelProtocol: ObservableObject {
    var uiState: PlatformBuildsUiState { get set }
    func load() async
    func loadMore() async
    func expireBuild(_ build: BuildModel) async
}

// MARK: - UiState

struct PlatformBuildsUiState {
    var appId: String
    var platform: String
    var account: AccountModel
    var builds: [BuildModel] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMorePages = false
    var error: String?
    var confirmExpireBuild: BuildModel?
    var isExpiringBuild = false
    var expireError: String?
    var toastMessage: ToastMessage?
}

// MARK: - Implementation

@MainActor
final class PlatformBuildsViewModel: PlatformBuildsViewModelProtocol {

    @Published var uiState: PlatformBuildsUiState

    private let keychain: KeyStorable
    private var lastPageResponse: Any?

    init(
        appId: String,
        platform: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = PlatformBuildsUiState(appId: appId, platform: platform, account: account)
        self.keychain = keychain
    }

    func load() async {
        uiState.isLoading = true
        uiState.error = nil
        uiState.builds = []
        lastPageResponse = nil

        do {
            guard let connection = createConnection() else {
                uiState.isLoading = false
                return
            }

            let page = try await connection.fetchBuildsPage(
                appId: uiState.appId,
                platform: uiState.platform,
                limit: 25,
                pageAfterResponse: nil
            )

            uiState.builds = page.builds
            uiState.hasMorePages = page.hasNextPage
            lastPageResponse = page.rawResponse

            Log.print.info("[PlatformBuilds] Loaded \(page.builds.count) builds for \(self.uiState.platform), hasMore: \(page.hasNextPage)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[PlatformBuilds] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func loadMore() async {
        guard uiState.hasMorePages, !uiState.isLoadingMore, lastPageResponse != nil else { return }
        uiState.isLoadingMore = true

        do {
            guard let connection = createConnection() else {
                uiState.isLoadingMore = false
                return
            }

            let page = try await connection.fetchBuildsPage(
                appId: uiState.appId,
                platform: uiState.platform,
                limit: 25,
                pageAfterResponse: lastPageResponse
            )

            uiState.builds.append(contentsOf: page.builds)
            uiState.hasMorePages = page.hasNextPage
            lastPageResponse = page.rawResponse

            Log.print.info("[PlatformBuilds] Loaded \(page.builds.count) more, total \(self.uiState.builds.count)")
        } catch {
            Log.print.error("[PlatformBuilds] Load more failed: \(error.localizedDescription)")
        }

        uiState.isLoadingMore = false
    }

    func expireBuild(_ build: BuildModel) async {
        uiState.isExpiringBuild = true
        uiState.expireError = nil
        do {
            guard let connection = createConnection() else {
                uiState.isExpiringBuild = false
                return
            }
            try await connection.expireBuild(buildId: build.id)
            if let idx = uiState.builds.firstIndex(where: { $0.id == build.id }) {
                uiState.builds[idx].isExpired = true
            }
            uiState.toastMessage = ToastMessage(String(localized: "Build expired"), icon: "clock.badge.xmark")
        } catch {
            uiState.expireError = error.localizedDescription
            Log.print.error("[PlatformBuilds] Expire failed: \(error.localizedDescription)")
        }
        uiState.isExpiringBuild = false
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
