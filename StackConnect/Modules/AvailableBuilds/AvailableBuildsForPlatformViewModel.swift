import Foundation

// MARK: - Protocol

@MainActor
protocol AvailableBuildsForPlatformViewModelProtocol: ObservableObject {
    var uiState: AvailableBuildsForPlatformUiState { get set }
    func load() async
    func loadMore() async
}

// MARK: - UiState

struct AvailableBuildsForPlatformUiState {
    var appId: String
    var platform: String
    var account: AccountModel
    var assignedBuildIds: Set<String>
    var builds: [BuildModel] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMorePages = false
    var error: String?
}

// MARK: - Implementation

@MainActor
final class AvailableBuildsForPlatformViewModel: AvailableBuildsForPlatformViewModelProtocol {

    @Published var uiState: AvailableBuildsForPlatformUiState

    private let keychain: KeyStorable
    private var lastPageResponse: Any?

    init(
        appId: String,
        platform: String,
        account: AccountModel,
        assignedBuildIds: Set<String>,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AvailableBuildsForPlatformUiState(
            appId: appId,
            platform: platform,
            account: account,
            assignedBuildIds: assignedBuildIds
        )
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
                processingStates: ["VALID"],
                limit: 25,
                pageAfterResponse: nil
            )

            uiState.builds = filterAssigned(page.builds)
            uiState.hasMorePages = page.hasNextPage
            lastPageResponse = page.rawResponse

            Log.print.info("[AvailableBuilds] Loaded \(self.uiState.builds.count) builds for \(self.uiState.platform), hasMore: \(page.hasNextPage)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[AvailableBuilds] Load failed: \(error.localizedDescription)")
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
                processingStates: ["VALID"],
                limit: 25,
                pageAfterResponse: lastPageResponse
            )

            uiState.builds.append(contentsOf: filterAssigned(page.builds))
            uiState.hasMorePages = page.hasNextPage
            lastPageResponse = page.rawResponse

            Log.print.info("[AvailableBuilds] Loaded \(page.builds.count) more, total \(self.uiState.builds.count)")
        } catch {
            Log.print.error("[AvailableBuilds] Load more failed: \(error.localizedDescription)")
        }

        uiState.isLoadingMore = false
    }

    private func filterAssigned(_ builds: [BuildModel]) -> [BuildModel] {
        builds.filter { !uiState.assignedBuildIds.contains($0.id) }
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
