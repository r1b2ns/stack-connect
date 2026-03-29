import Foundation

// MARK: - Protocol

@MainActor
protocol VersionListViewModelProtocol: ObservableObject {
    var uiState: VersionListUiState { get set }
    func loadVersions() async
}

// MARK: - UiState

struct VersionListUiState {
    var versions: [AppStoreVersionModel] = []
    var isLoading = false
    var isSyncing = false
    var showSyncToast = false
    var syncError: String?
    var appId: String
    var platform: AppPlatform
    var account: AccountModel
}

// MARK: - Implementation

@MainActor
final class VersionListViewModel: VersionListViewModelProtocol {

    @Published var uiState: VersionListUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        appId: String,
        platform: AppPlatform,
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = VersionListUiState(appId: appId, platform: platform, account: account)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func loadVersions() async {
        uiState.isLoading = true

        // 1. Load cached
        do {
            let cached: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)
            let filtered = cached.filter { $0.appId == self.uiState.appId && $0.platform == self.uiState.platform }
            if !filtered.isEmpty {
                uiState.versions = filtered
                uiState.isLoading = false
                uiState.showSyncToast = true
            }
        } catch {
            Log.print.error("[VersionList] Cache load failed: \(error.localizedDescription)")
        }

        // 2. Sync from API
        uiState.isSyncing = true

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(self.uiState.account.id)") else {
                uiState.isLoading = false
                uiState.isSyncing = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            let allVersions = try await connection.fetchAppStoreVersions(appId: uiState.appId, limit: 200)
            let platformVersions = allVersions.filter { $0.platform == self.uiState.platform }

            uiState.versions = platformVersions

            for version in platformVersions {
                try await storage.save(version, id: "version.\(version.id)")
            }

            Log.print.info("[VersionList] Synced \(platformVersions.count) \(self.uiState.platform.displayName) versions")

        } catch {
            uiState.syncError = error.localizedDescription
            Log.print.error("[VersionList] Sync failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        uiState.isSyncing = false
    }
}
