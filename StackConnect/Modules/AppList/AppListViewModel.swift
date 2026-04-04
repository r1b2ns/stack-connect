import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol AppListViewModelProtocol: ObservableObject {
    var uiState: AppListUiState { get set }
    func loadApps() async
    func toggleArchive(app: AppModel) async
    func toggleFavorite(app: AppModel) async
    func previewImportName(from url: URL) -> String?
    func importAccount(from url: URL, customName: String?) async -> String?
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
                    isFavorite: cached?.isFavorite ?? false
                )
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
    }

    private func enrichApps(_ apps: [AppModel], using connection: AppleAccountConnection) async -> [AppModel] {
        let enrichments = await withTaskGroup(of: AppEnrichment.self) { group in
            for app in apps {
                let appId = app.id
                let hasIcon = app.iconUrl != nil
                group.addTask {
                    async let iconUrl = hasIcon ? nil : connection.fetchIconUrl(appId: appId)
                    let versions = (try? await connection.fetchAppStoreVersions(appId: appId, limit: 1)) ?? []
                    let latestVersion = versions.first

                    let icon = await iconUrl

                    return AppEnrichment(
                        appId: appId,
                        iconUrl: icon,
                        appStoreState: latestVersion?.appStoreState,
                        versionString: latestVersion?.versionString,
                        lastModifiedDate: latestVersion?.createdDate
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

    // MARK: - Import

    func previewImportName(from url: URL) -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = dict["name"] as? String, !name.isEmpty else {
            return nil
        }
        return name
    }

    func importAccount(from url: URL, customName: String?) async -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { return String(localized: "Failed to read file.") }

        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(localized: "Invalid JSON format.")
        }

        guard let name = dict["name"] as? String, !name.isEmpty else {
            return String(localized: "Missing or invalid 'name' field.")
        }
        guard let providerRaw = dict["providerType"] as? String,
              let providerType = ProviderType(rawValue: providerRaw) else {
            return String(localized: "Missing or invalid 'providerType' field.")
        }
        guard providerType == uiState.account.providerType else {
            return String(localized: "This file contains a \(providerType.displayName) account, but this is the \(uiState.account.providerType.displayName) section.")
        }

        let emptyRules = AccountRules(apps: [], version: [], users: [], review: [], testFlight: [], analytics: [])
        var rules = emptyRules
        if let rulesDict = dict["rules"] as? [String: [String]] {
            rules = AccountRules(
                apps: rulesDict["apps"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                version: rulesDict["version"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                users: rulesDict["users"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                review: rulesDict["review"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                testFlight: rulesDict["testFlight"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                analytics: rulesDict["analytics"]?.compactMap { AccountPermission(rawValue: $0) } ?? []
            )
        }

        guard let credsDict = dict["credentials"] as? [String: String] else {
            return String(localized: "Missing or invalid 'credentials' field.")
        }

        let allAccounts = (try? await storage.fetchAll(AccountModel.self)) ?? []
        let sameTypeAccounts = allAccounts.filter { $0.providerType == providerType }
        let accountId = UUID().uuidString

        switch providerType {
        case .apple:
            guard let issuerID = credsDict["issuerID"], !issuerID.isEmpty,
                  let privateKeyID = credsDict["privateKeyID"], !privateKeyID.isEmpty,
                  let privateKey = credsDict["privateKey"], !privateKey.isEmpty else {
                return String(localized: "Invalid Apple credentials.")
            }
            for existing in sameTypeAccounts {
                if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.privateKey == privateKey {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            keychain.setObject(AppleCredentials(issuerID: issuerID, privateKeyID: privateKeyID, privateKey: privateKey), forKey: "credentials.\(accountId)")
        case .firebase:
            guard let json = credsDict["serviceAccountJSON"], !json.isEmpty else {
                return String(localized: "Invalid Firebase credentials.")
            }
            for existing in sameTypeAccounts {
                if let creds: FirebaseCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.serviceAccountJSON == json {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            keychain.setObject(FirebaseCredentials(serviceAccountJSON: json), forKey: "credentials.\(accountId)")
        case .googlePlay:
            guard let json = credsDict["serviceAccountJSON"], !json.isEmpty else {
                return String(localized: "Invalid Google Play credentials.")
            }
            for existing in sameTypeAccounts {
                if let creds: GooglePlayCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.serviceAccountJSON == json {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: "credentials.\(accountId)")
        }

        let accountName = (customName?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            ? customName!.trimmingCharacters(in: .whitespaces) : name
        let account = AccountModel(id: accountId, name: accountName, providerType: providerType, rules: rules, origin: .imported)

        do {
            try await storage.save(account, id: account.id)
            Log.print.info("[AppList] Imported account: \(accountName)")
            return nil
        } catch {
            return String(localized: "Failed to save imported account.")
        }
    }
}
