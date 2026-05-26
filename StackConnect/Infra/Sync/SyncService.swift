import Foundation

// MARK: - State

struct SyncState: Equatable {
    var isSyncing = false
    var accountsInProgress: Set<String> = []
    var lastSyncedAt: Date?
    var lastError: String?
}

// MARK: - Service

/// Orchestrates background sync of accounts and their apps.
///
/// Per-account fetches run in parallel via TaskGroup; writes serialize through
/// the SwiftDataStorable actor. Coalesces concurrent `syncAll()` calls so
/// repeated invocations don't pile up.
@MainActor
final class SyncService: ObservableObject {

    static let shared = SyncService()

    @Published private(set) var state = SyncState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private var rootTask: Task<Void, Never>?

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    /// Fire-and-forget. Safe to call repeatedly — already-running syncs are coalesced
    /// (subsequent callers receive the same in-flight Task and can await it if needed).
    @discardableResult
    func syncAll() -> Task<Void, Never> {
        if let rootTask {
            Log.print.info("[Sync] syncAll coalesced into in-flight sync")
            return rootTask
        }
        let task = Task { [weak self] in
            await self?.performSyncAll()
            self?.rootTask = nil
        }
        rootTask = task
        return task
    }

    // MARK: - Private (MainActor)

    private func performSyncAll() async {
        state.isSyncing = true
        state.lastError = nil

        let accounts: [AccountModel]
        do {
            let all: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            accounts = all.filter { $0.providerType == .apple }
        } catch {
            state.lastError = error.localizedDescription
            state.isSyncing = false
            Log.print.error("[Sync] Failed to load accounts: \(error.localizedDescription)")
            return
        }

        guard !accounts.isEmpty else {
            state.isSyncing = false
            state.lastSyncedAt = .now
            return
        }

        // Snapshot credentials on MainActor — KeyStorable isn't Sendable, but
        // AppleCredentials is a Codable value type so it's safe to ship across tasks.
        let prepared: [(AccountModel, AppleCredentials?)] = accounts.map { account in
            let creds: AppleCredentials? = keychain.object(forKey: "credentials.\(account.id)")
            return (account, creds)
        }

        Log.print.info("[Sync] Starting parallel sync for \(accounts.count) Apple account(s)")
        let storage = self.storage

        await withTaskGroup(of: Void.self) { group in
            for (account, credentials) in prepared {
                group.addTask { [weak self] in
                    await self?.markInProgress(account.id, started: true)
                    await SyncService.runAccountSync(
                        account: account,
                        credentials: credentials,
                        storage: storage
                    )
                    await self?.markInProgress(account.id, started: false)
                }
            }
            await group.waitForAll()
        }

        state.lastSyncedAt = .now
        state.isSyncing = false
        Log.print.info("[Sync] syncAll completed")
    }

    private func markInProgress(_ accountId: String, started: Bool) {
        if started {
            state.accountsInProgress.insert(accountId)
        } else {
            state.accountsInProgress.remove(accountId)
        }
    }

    // MARK: - Private (off MainActor)

    private nonisolated static func runAccountSync(
        account: AccountModel,
        credentials: AppleCredentials?,
        storage: PersistentStorable
    ) async {
        guard let credentials else {
            Log.print.error("[Sync] No credentials for \(account.name)")
            await saveMetadata(storage: storage, accountId: account.id, appsSynced: 0, error: "Missing credentials")
            return
        }

        let connection = AppleAccountConnection(credentials: credentials)

        do {
            let remoteApps = try await connection.fetchApps()
            let allCached: [AppModel] = (try? await storage.fetchAll(AppModel.self)) ?? []
            let cachedMap = Dictionary(uniqueKeysWithValues:
                allCached.filter { $0.accountId == account.id }.map { ($0.id, $0) }
            )

            let baseApps: [AppModel] = remoteApps.map { info in
                let cached = cachedMap[info.id]
                return AppModel(
                    id: info.id,
                    name: info.name,
                    bundleId: info.bundleId,
                    platform: info.platform,
                    accountId: account.id,
                    iconUrl: cached?.iconUrl,
                    appStoreState: cached?.appStoreState,
                    versionString: cached?.versionString,
                    lastModifiedDate: cached?.lastModifiedDate,
                    isArchived: cached?.isArchived ?? false,
                    isFavorite: cached?.isFavorite ?? false
                )
            }

            let enriched = await enrichApps(baseApps.filter { !$0.isArchived }, connection: connection)
            let enrichedMap = Dictionary(uniqueKeysWithValues: enriched.map { ($0.id, $0) })
            let finalApps = baseApps.map { enrichedMap[$0.id] ?? $0 }

            for app in finalApps {
                do {
                    try await storage.save(app, id: "\(account.id).\(app.id)")
                } catch {
                    Log.print.error("[Sync] Save failed for \(app.name): \(error.localizedDescription)")
                }
            }

            await saveMetadata(
                storage: storage,
                accountId: account.id,
                appsSynced: finalApps.count,
                error: nil
            )
            Log.print.info("[Sync] \(account.name): \(finalApps.count) apps synced")
        } catch {
            await saveMetadata(
                storage: storage,
                accountId: account.id,
                appsSynced: 0,
                error: error.localizedDescription
            )
            Log.print.error("[Sync] \(account.name) failed: \(error.localizedDescription)")
        }
    }

    private struct AppEnrichment: Sendable {
        let appId: String
        let iconUrl: String?
        let appStoreState: AppStoreState?
        let versionString: String?
        let lastModifiedDate: Date?
    }

    private nonisolated static func enrichApps(
        _ apps: [AppModel],
        connection: AppleAccountConnection
    ) async -> [AppModel] {
        let enrichments = await withTaskGroup(of: AppEnrichment.self) { group in
            for app in apps {
                let appId = app.id
                let needsIcon = app.iconUrl == nil
                group.addTask {
                    async let iconUrl: String? = needsIcon ? connection.fetchIconUrl(appId: appId) : nil
                    let versions = (try? await connection.fetchAppStoreVersions(appId: appId, limit: 1)) ?? []
                    let latest = versions.first
                    let icon = await iconUrl
                    return AppEnrichment(
                        appId: appId,
                        iconUrl: icon,
                        appStoreState: latest?.appStoreState,
                        versionString: latest?.versionString,
                        lastModifiedDate: latest?.createdDate
                    )
                }
            }
            var result: [AppEnrichment] = []
            for await item in group { result.append(item) }
            return result
        }

        let map = Dictionary(uniqueKeysWithValues: enrichments.map { ($0.appId, $0) })
        return apps.map { app in
            var updated = app
            if let e = map[app.id] {
                if let url = e.iconUrl { updated.iconUrl = url }
                if let state = e.appStoreState { updated.appStoreState = state }
                if let ver = e.versionString { updated.versionString = ver }
                if let date = e.lastModifiedDate { updated.lastModifiedDate = date }
                updated.hasReviewPending = updated.appStoreState?.isReviewPending ?? false
            }
            return updated
        }
    }

    private nonisolated static func saveMetadata(
        storage: PersistentStorable,
        accountId: String,
        appsSynced: Int,
        error: String?
    ) async {
        let metadata = SyncMetadata(
            accountId: accountId,
            lastSyncedAt: .now,
            lastError: error,
            appsSynced: appsSynced
        )
        try? await storage.save(metadata, id: "sync.account.\(accountId)")
    }
}
