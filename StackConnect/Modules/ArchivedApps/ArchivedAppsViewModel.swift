import Foundation
import StackProtocols
import WidgetKit

// MARK: - Protocol

@MainActor
protocol ArchivedAppsViewModelProtocol: ObservableObject {
    var uiState: ArchivedAppsUiState { get set }
    func loadApps() async
    func unarchive(app: AppModel) async
}

// MARK: - UiState

struct ArchivedAppsUiState {
    var apps: [AppModel] = []
    var isLoading = false
    var isSyncing = false
    var account: AccountModel
    var searchQuery = ""
    var toastMessage: ToastMessage?

    var filteredApps: [AppModel] {
        let archived = apps.filter { $0.isArchived }
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return archived }
        let query = searchQuery.lowercased()
        return archived.filter {
            $0.name.lowercased().contains(query) ||
            $0.bundleId.lowercased().contains(query)
        }
    }
}

// MARK: - Implementation

@MainActor
final class ArchivedAppsViewModel: ArchivedAppsViewModelProtocol {

    @Published var uiState: ArchivedAppsUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = ArchivedAppsUiState(account: account)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func loadApps() async {
        uiState.isLoading = true

        // Load archived apps from SwiftData
        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let archivedApps = allApps
                .filter { $0.accountId == self.uiState.account.id && $0.isArchived }
                .sorted { a, b in
                    switch (a.lastModifiedDate, b.lastModifiedDate) {
                    case let (dateA?, dateB?): return dateA > dateB
                    case (_?, nil):            return true
                    case (nil, _?):            return false
                    case (nil, nil):           return a.name < b.name
                    }
                }
            uiState.apps = archivedApps
        } catch {
            Log.print.error("[ArchivedApps] Failed to load apps: \(error.localizedDescription)")
        }

        uiState.isLoading = false

        // Sync archived apps from API
        uiState.isSyncing = true
        do {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(self.uiState.account.id)") else {
                uiState.isSyncing = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            let archivedApps = uiState.apps.filter { $0.isArchived }

            for var app in archivedApps {
                if let icon = await connection.fetchIconUrl(appId: app.id) {
                    app.iconUrl = icon
                }
                if let versions = try? await connection.fetchAppStoreVersions(appId: app.id, limit: 1),
                   let latest = versions.first {
                    app.appStoreState = latest.appStoreState
                    app.versionString = latest.versionString
                    app.lastModifiedDate = latest.createdDate
                }
                if let idx = uiState.apps.firstIndex(where: { $0.id == app.id }) {
                    uiState.apps[idx] = app
                }
                try await storage.save(app, id: "\(self.uiState.account.id).\(app.id)")
            }

            Log.print.info("[ArchivedApps] Synced \(archivedApps.count) archived apps")
        } catch {
            Log.print.error("[ArchivedApps] Sync failed: \(error.localizedDescription)")
        }

        uiState.isSyncing = false
    }

    func unarchive(app: AppModel) async {
        guard let idx = uiState.apps.firstIndex(where: { $0.id == app.id }) else { return }
        uiState.apps[idx].isArchived = false
        let updated = uiState.apps[idx]

        do {
            try await storage.save(updated, id: "\(uiState.account.id).\(updated.id)")
            // Refresh widgets so the unarchived app's reviews reappear immediately.
            WidgetCenter.shared.reloadAllTimelines()
            uiState.apps.removeAll { $0.id == updated.id }
            uiState.toastMessage = ToastMessage(String(localized: "App unarchived"), icon: "archivebox.fill")
            Log.print.info("[ArchivedApps] Unarchived \(updated.name)")
        } catch {
            uiState.apps[idx].isArchived = true // revert
            Log.print.error("[ArchivedApps] Unarchive failed: \(error.localizedDescription)")
        }
    }
}
