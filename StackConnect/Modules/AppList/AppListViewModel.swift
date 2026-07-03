import Foundation
import StackProtocols
import WidgetKit

// MARK: - Protocol

@MainActor
protocol AppListViewModelProtocol: ObservableObject {
    var uiState: AppListUiState { get set }
    func loadApps() async
    func toggleArchive(app: AppModel) async
    func toggleFavorite(app: AppModel) async
}

// MARK: - UiState

struct AppListUiState {
    var apps: [AppModel] = []
    var isLoading = false
    var isSyncing = false
    var showSyncToast = false
    var syncError: String?
    var account: AccountModel
    var searchQuery = ""
    var toastMessage: ToastMessage?

    /// Non-archived apps, filtered by search query.
    var filteredApps: [AppModel] {
        let nonArchived = apps.filter { !$0.isArchived }
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return nonArchived }
        let query = searchQuery.lowercased()
        return nonArchived.filter {
            $0.name.lowercased().contains(query) ||
            $0.bundleId.lowercased().contains(query)
        }
    }

    var favoriteApps: [AppModel] {
        filteredApps.filter { $0.isFavorite }
    }

    var regularApps: [AppModel] {
        filteredApps.filter { !$0.isFavorite }
    }
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

        // 1. Load cached apps from SwiftData (offline-first)
        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let cachedApps = allApps
                .filter { $0.accountId == self.uiState.account.id }
                .sorted { a, b in
                    switch (a.lastModifiedDate, b.lastModifiedDate) {
                    case let (dateA?, dateB?): return dateA > dateB
                    case (_?, nil):            return true
                    case (nil, _?):            return false
                    case (nil, nil):           return a.name < b.name
                    }
                }
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
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(self.uiState.account.id)") else {
                Log.print.error("[AppList] No credentials found for account: \(self.uiState.account.name)")
                uiState.isLoading = false
                uiState.isSyncing = false
                return
            }

            let connection = AppleAccountConnection(credentials: credentials)
            let remoteApps = try await connection.fetchApps()

            var appModels = remoteApps.map { appInfo in
                let cached = self.uiState.apps.first { $0.id == appInfo.id }
                return AppModel(
                    id: appInfo.id,
                    name: appInfo.name,
                    bundleId: appInfo.bundleId,
                    platform: appInfo.platform,
                    accountId: self.uiState.account.id,
                    iconUrl: cached?.iconUrl,
                    appStoreState: cached?.appStoreState,
                    versionString: cached?.versionString,
                    lastModifiedDate: cached?.lastModifiedDate,
                    isArchived: cached?.isArchived ?? false,
                    isFavorite: cached?.isFavorite ?? false,
                    platformVersions: cached?.platformVersions,
                    awaitingVersions: cached?.awaitingVersions
                )
            }.sorted { a, b in
                switch (a.lastModifiedDate, b.lastModifiedDate) {
                case let (dateA?, dateB?): return dateA > dateB
                case (_?, nil):            return true
                case (nil, _?):            return false
                case (nil, nil):           return a.name < b.name
                }
            }

            // 3. Enrich only non-archived apps (expensive API calls)
            let nonArchived = appModels.filter { !$0.isArchived }
            let enriched = await enrichApps(nonArchived, using: connection)
            let enrichedMap = Dictionary(uniqueKeysWithValues: enriched.map { ($0.id, $0) })

            appModels = appModels.map { app in
                enrichedMap[app.id] ?? app
            }

            uiState.apps = appModels

            // 4. Persist enriched models to SwiftData
            for app in appModels {
                try await storage.save(app, id: "\(self.uiState.account.id).\(app.id)")
            }

            Log.print.info("[AppList] Synced \(appModels.count) apps for account: \(self.uiState.account.name)")

        } catch {
            uiState.syncError = error.localizedDescription
            Log.print.error("[AppList] Sync failed: \(error.localizedDescription)")
        }

        uiState.isLoading = false
        uiState.isSyncing = false
    }

    func toggleArchive(app: AppModel) async {
        guard let idx = uiState.apps.firstIndex(where: { $0.id == app.id }) else { return }
        uiState.apps[idx].isArchived.toggle()
        let updated = uiState.apps[idx]

        do {
            try await storage.save(updated, id: "\(uiState.account.id).\(updated.id)")
            // Refresh widgets so archived apps' reviews disappear immediately.
            WidgetCenter.shared.reloadAllTimelines()
            let text = updated.isArchived
                ? String(localized: "App archived")
                : String(localized: "App unarchived")
            uiState.toastMessage = ToastMessage(text, icon: "archivebox.fill")
            Log.print.info("[AppList] Toggled archive for \(updated.name): \(updated.isArchived)")
        } catch {
            uiState.apps[idx].isArchived.toggle() // revert
            Log.print.error("[AppList] Toggle archive failed: \(error.localizedDescription)")
        }
    }

    func toggleFavorite(app: AppModel) async {
        guard let idx = uiState.apps.firstIndex(where: { $0.id == app.id }) else { return }
        uiState.apps[idx].isFavorite.toggle()
        let updated = uiState.apps[idx]

        do {
            try await storage.save(updated, id: "\(uiState.account.id).\(updated.id)")
            let text = updated.isFavorite
                ? String(localized: "Added to favorites")
                : String(localized: "Removed from favorites")
            uiState.toastMessage = ToastMessage(text, icon: updated.isFavorite ? "star.fill" : "star")
            Log.print.info("[AppList] Toggled favorite for \(updated.name): \(updated.isFavorite)")
        } catch {
            uiState.apps[idx].isFavorite.toggle() // revert
            Log.print.error("[AppList] Toggle favorite failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private struct AppEnrichment: Sendable {
        let appId: String
        let iconUrl: String?
        let appStoreState: AppStoreState?
        let versionString: String?
        let lastModifiedDate: Date?
        let platformVersions: [AppPlatformVersion]
        let awaitingVersions: [AppPlatformVersion]
    }

    private func enrichApps(_ apps: [AppModel], using connection: AppleAccountConnection) async -> [AppModel] {
        let enrichments = await withTaskGroup(of: AppEnrichment.self) { group in
            for app in apps {
                let appId = app.id
                let hasIcon = app.iconUrl != nil
                group.addTask {
                    async let iconUrl = hasIcon ? nil : connection.fetchIconUrl(appId: appId)
                    let versions = (try? await connection.fetchAppStoreVersions(appId: appId, limit: 20)) ?? []
                    // Most recent first, so the overall "latest" and the per-platform
                    // latest both come out correctly.
                    let sorted = versions.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
                    let latestVersion = sorted.first

                    var platformVersions: [AppPlatformVersion] = []
                    var seenPlatforms = Set<String>()
                    for version in sorted {
                        guard let platform = version.platform?.rawValue, !seenPlatforms.contains(platform) else { continue }
                        seenPlatforms.insert(platform)
                        platformVersions.append(
                            AppPlatformVersion(
                                platform: platform,
                                appStoreState: version.appStoreState,
                                versionString: version.versionString,
                                id: version.id
                            )
                        )
                    }

                    // Every awaiting-eligible version (not deduped to latest-per-platform),
                    // so a still-phasing readyForSale version survives a newer prepared one.
                    let awaitingVersions: [AppPlatformVersion] = sorted.compactMap { version in
                        guard version.appStoreState?.isAwaitingReleaseEligible == true,
                              let platform = version.platform?.rawValue else { return nil }
                        return AppPlatformVersion(
                            platform: platform,
                            appStoreState: version.appStoreState,
                            versionString: version.versionString,
                            id: version.id
                        )
                    }

                    let icon = await iconUrl

                    return AppEnrichment(
                        appId: appId,
                        iconUrl: icon,
                        appStoreState: latestVersion?.appStoreState,
                        versionString: latestVersion?.versionString,
                        lastModifiedDate: latestVersion?.createdDate,
                        platformVersions: platformVersions,
                        awaitingVersions: awaitingVersions
                    )
                }
            }

            var result: [AppEnrichment] = []
            for await enrichment in group {
                result.append(enrichment)
            }
            return result
        }

        let enrichmentMap = Dictionary(uniqueKeysWithValues: enrichments.map { ($0.appId, $0) })

        var enrichedApps = apps.map { app in
            var enriched = app
            if let e = enrichmentMap[app.id] {
                if let url = e.iconUrl { enriched.iconUrl = url }
                if let state = e.appStoreState { enriched.appStoreState = state }
                if let ver = e.versionString { enriched.versionString = ver }
                if let date = e.lastModifiedDate { enriched.lastModifiedDate = date }
                if !e.platformVersions.isEmpty {
                    enriched.platformVersions = e.platformVersions
                    enriched.awaitingVersions = e.awaitingVersions
                }
                enriched.hasReviewPending = enriched.appStoreState?.isReviewPending ?? false
            }
            return enriched
        }

        // Sort by last modified date (most recent first), apps without date at the end
        enrichedApps.sort { a, b in
            switch (a.lastModifiedDate, b.lastModifiedDate) {
            case let (dateA?, dateB?): return dateA > dateB
            case (_?, nil):            return true
            case (nil, _?):            return false
            case (nil, nil):           return a.name < b.name
            }
        }

        return enrichedApps
    }

}
