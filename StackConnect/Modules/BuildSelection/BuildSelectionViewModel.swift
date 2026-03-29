import Foundation

// MARK: - Protocol

@MainActor
protocol BuildSelectionViewModelProtocol: ObservableObject {
    var uiState: BuildSelectionUiState { get set }
    func loadBuilds() async
    func selectBuild(_ build: BuildModel) async
}

// MARK: - UiState

struct BuildSelectionUiState {
    var builds: [BuildModel] = []
    var currentBuildId: String?
    var isLoading = false
    var isAttaching = false
    var error: String?
    var didSelect = false
    var versionId: String
    var appId: String
    var account: AccountModel
}

// MARK: - Implementation

@MainActor
final class BuildSelectionViewModel: BuildSelectionViewModelProtocol {

    @Published var uiState: BuildSelectionUiState

    private let keychain: KeyStorable

    init(
        versionId: String,
        appId: String,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = BuildSelectionUiState(versionId: versionId, appId: appId, account: account)
        self.keychain = keychain
    }

    func loadBuilds() async {
        uiState.isLoading = true

        guard let connection = createConnection() else {
            uiState.isLoading = false
            return
        }

        do {
            async let buildsTask = connection.fetchBuilds(appId: uiState.appId, limit: 50)
            async let currentTask = connection.fetchCurrentBuild(versionId: uiState.versionId)

            let builds = try await buildsTask
            let current = try await currentTask

            uiState.builds = builds
            uiState.currentBuildId = current?.id
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[BuildSelection] Load failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
    }

    func selectBuild(_ build: BuildModel) async {
        guard build.id != uiState.currentBuildId else { return }

        uiState.isAttaching = true

        guard let connection = createConnection() else {
            uiState.isAttaching = false
            return
        }

        do {
            try await connection.attachBuild(versionId: uiState.versionId, buildId: build.id)
            uiState.currentBuildId = build.id
            uiState.didSelect = true
            Log.print.info("[BuildSelection] Attached build \(build.version ?? build.id)")
        } catch {
            uiState.error = error.localizedDescription
            Log.print.error("[BuildSelection] Attach failed: \(error.localizedDescription)")
        }

        uiState.isAttaching = false
    }

    private func createConnection() -> AppleAccountConnection? {
        guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else {
            return nil
        }
        return AppleAccountConnection(credentials: credentials)
    }
}
