import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AppListViewModelProtocol: ObservableObject {
    var uiState: AppListUiState { get set }
    func loadApps() async
}

// MARK: - UiState

struct AppListUiState {
    var apps: [AppModel] = []
    var isLoading = false
    var isSyncing = false
    var showSyncToast = false
    var syncError: String?
    var account: AccountModel
}

// MARK: - Implementation

@MainActor
final class AppListViewModel: AppListViewModelProtocol {

    @Published var uiState: AppListUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AppListUiState(account: account)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func loadApps() async {
        uiState.isLoading = true

        // 1. Load cached apps from SwiftData
        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let cachedApps = allApps.filter { $0.accountId == self.uiState.account.id }
            if !cachedApps.isEmpty {
                uiState.apps = cachedApps
                uiState.isLoading = false
            }
        } catch {
            Log.print.error("[AppList] Failed to load cached apps: \(error.localizedDescription)")
        }

        // 2. Sync from API
        uiState.isSyncing = true
        if !uiState.apps.isEmpty {
            uiState.showSyncToast = true
        }

        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(self.self.uiState.account.id)") else {
                Log.print.error("[AppList] No credentials found for account: \(self.self.uiState.account.name)")
                uiState.isLoading = false
                uiState.isSyncing = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            let remoteApps = try await connection.fetchApps()

            let appModels = remoteApps.map { appInfo in
                AppModel(
                    id: appInfo.id,
                    name: appInfo.name,
                    bundleId: appInfo.bundleId,
                    platform: appInfo.platform,
                    accountId: self.uiState.account.id
                )
            }

            // Save each app to SwiftData
            for app in appModels {
                try await storage.save(app, id: "\(self.uiState.account.id).\(app.id)")
            }

            uiState.apps = appModels
            Log.print.info("[AppList] Synced \(appModels.count) apps for account: \(self.uiState.account.name)")

        } catch {
            uiState.syncError = error.localizedDescription
            Log.print.error("[AppList] Sync failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        uiState.isSyncing = false
    }
}
