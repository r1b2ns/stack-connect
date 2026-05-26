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
        let versionsLimit = 200
        uiState.isLoading = true

        // 1. Load cached
        do {
            let cached: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)
            let filtered = cached.filter {
                $0.appId == self.uiState.appId && $0.platform == self.uiState.platform
            }.sorted(by: {
                $0.versionString ?? "" > $1.versionString ?? ""
            })
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
            let allVersions = try await connection.fetchAppStoreVersions(appId: uiState.appId, limit: versionsLimit)
            let platformVersions = allVersions.filter { $0.platform == self.uiState.platform }

            uiState.versions = platformVersions

            // Persist in a detached Task so a view dismissal mid-loop (which cancels
            // `.task`) doesn't truncate the writes. Reconciliation runs at the end.
            persistSync(
                versions: platformVersions,
                hitCap: allVersions.count >= versionsLimit
            )

            Log.print.info("[VersionList] Synced \(platformVersions.count) \(self.uiState.platform.displayName) versions")

        } catch {
            uiState.syncError = error.localizedDescription
            Log.print.error("[VersionList] Sync failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        uiState.isSyncing = false
    }

    // MARK: - Private

    private func persistSync(versions: [AppStoreVersionModel], hitCap: Bool) {
        let storage = self.storage
        let appId = uiState.appId
        let platform = uiState.platform

        Task.detached(priority: .utility) {
            for version in versions {
                do {
                    try await storage.save(version, id: "version.\(version.id)")
                } catch {
                    Log.print.error("[VersionList] Failed to persist version \(version.id): \(error.localizedDescription)")
                }
            }

            if !hitCap {
                await Self.pruneStaleVersions(
                    storage: storage,
                    appId: appId,
                    platform: platform,
                    returned: versions
                )
            }
        }
    }

    private static func pruneStaleVersions(
        storage: PersistentStorable,
        appId: String,
        platform: AppPlatform,
        returned: [AppStoreVersionModel]
    ) async {
        let returnedIds = Set(returned.map { $0.id })
        do {
            let allCached: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)
            let stale = allCached.filter {
                $0.appId == appId
                    && $0.platform == platform
                    && !returnedIds.contains($0.id)
            }
            for version in stale {
                try? await storage.delete(AppStoreVersionModel.self, id: "version.\(version.id)")
            }
            if !stale.isEmpty {
                Log.print.info("[VersionList] Pruned \(stale.count) stale cached \(platform.displayName) versions")
            }
        } catch {
            Log.print.error("[VersionList] Reconciliation failed: \(error.localizedDescription)")
        }
    }
}
