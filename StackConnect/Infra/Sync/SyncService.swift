import Foundation

// MARK: - State

struct SyncState: Equatable {
    var isSyncing = false
    var accountsInProgress: Set<String> = []
    var lastSyncedAt: Date?
    var lastError: String?
}

// MARK: - Mode

enum SyncMode: Sendable {
    /// Apps, enrichment, reviews, phased. Used at foreground launch + pull-to-refresh.
    case full
    /// Apps + enrichment + phased only — skips reviews to fit in BG refresh budgets.
    case lightweight
}

// MARK: - Service

/// Orchestrates background sync of accounts and their apps.
///
/// Per-account fetches run in parallel via TaskGroup; writes serialize through
/// the SwiftDataStorable actor. Coalesces concurrent `syncAll()` calls so
/// repeated invocations don't pile up.
@MainActor
final class SyncService: ObservableObject {

    typealias AppleConnectionFactory = (AppleCredentials) -> any AppleAccountSyncing

    static let shared = SyncService()

    @Published private(set) var state = SyncState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let appleConnectionFactory: AppleConnectionFactory
    private var rootTask: Task<Void, Never>?

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        appleConnectionFactory: AppleConnectionFactory? = nil
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.appleConnectionFactory = appleConnectionFactory ?? { AppleAccountConnection(credentials: $0) }
    }

    /// Fire-and-forget. Safe to call repeatedly — already-running syncs are coalesced
    /// (subsequent callers receive the same in-flight Task and can await it if needed).
    @discardableResult
    func syncAll(mode: SyncMode = .full) -> Task<Void, Never> {
        if let rootTask {
            Log.print.info("[Sync] syncAll coalesced into in-flight sync")
            return rootTask
        }
        let task = Task { [weak self] in
            await self?.performSyncAll(mode: mode)
            self?.rootTask = nil
        }
        rootTask = task
        return task
    }

    // MARK: - Private (MainActor)

    private func performSyncAll(mode: SyncMode) async {
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

        // Build the per-account connections on MainActor (Keychain isn't Sendable).
        // The connections themselves are Sendable so they're safe to ship to detached work.
        let prepared: [(AccountModel, (any AppleAccountSyncing)?)] = accounts.map { account in
            let creds: AppleCredentials? = keychain.object(forKey: "credentials.\(account.id)")
            let connection = creds.map(appleConnectionFactory)
            return (account, connection)
        }

        Log.print.info("[Sync] Starting \(mode == .lightweight ? "lightweight " : "")parallel sync for \(accounts.count) Apple account(s)")
        let storage = self.storage

        await withTaskGroup(of: Void.self) { group in
            for (account, connection) in prepared {
                group.addTask { [weak self] in
                    await self?.markInProgress(account.id, started: true)
                    await SyncService.runAccountSync(
                        account: account,
                        connection: connection,
                        storage: storage,
                        mode: mode
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
        connection: (any AppleAccountSyncing)?,
        storage: PersistentStorable,
        mode: SyncMode
    ) async {
        guard let connection else {
            Log.print.error("[Sync] No credentials for \(account.name)")
            await saveMetadata(storage: storage, accountId: account.id, appsSynced: 0, error: "Missing credentials")
            return
        }

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

            let (enriched, versionIdByAppId) = await enrichApps(
                baseApps.filter { !$0.isArchived },
                connection: connection
            )
            let enrichedMap = Dictionary(uniqueKeysWithValues: enriched.map { ($0.id, $0) })
            let finalApps = baseApps.map { enrichedMap[$0.id] ?? $0 }

            for app in finalApps {
                do {
                    try await storage.save(app, id: "\(account.id).\(app.id)")
                } catch {
                    Log.print.error("[Sync] Save failed for \(app.name): \(error.localizedDescription)")
                }
            }

            let activeApps = finalApps.filter { !$0.isArchived }
            let phasedSaved = await syncPhased(
                for: activeApps,
                versionIdByAppId: versionIdByAppId,
                connection: connection,
                storage: storage
            )

            let reviewsSaved: Int
            switch mode {
            case .full:
                reviewsSaved = await syncReviews(
                    for: activeApps,
                    connection: connection,
                    storage: storage
                )
            case .lightweight:
                reviewsSaved = 0
            }

            await saveMetadata(
                storage: storage,
                accountId: account.id,
                appsSynced: finalApps.count,
                error: nil
            )
            let modeLabel = mode == .lightweight ? "lightweight" : "full"
            Log.print.info("[Sync] \(account.name): \(finalApps.count) apps, \(reviewsSaved) reviews, \(phasedSaved) phased (\(modeLabel))")
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
        let currentVersionId: String?
    }

    private nonisolated static func enrichApps(
        _ apps: [AppModel],
        connection: any AppleAccountSyncing
    ) async -> (enriched: [AppModel], versionIdByAppId: [String: String]) {
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
                        lastModifiedDate: latest?.createdDate,
                        currentVersionId: latest?.id
                    )
                }
            }
            var result: [AppEnrichment] = []
            for await item in group { result.append(item) }
            return result
        }

        let map = Dictionary(uniqueKeysWithValues: enrichments.map { ($0.appId, $0) })
        let enrichedApps = apps.map { app -> AppModel in
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
        let versionIds = Dictionary(uniqueKeysWithValues:
            enrichments.compactMap { e -> (String, String)? in
                guard let id = e.currentVersionId else { return nil }
                return (e.appId, id)
            }
        )
        return (enrichedApps, versionIds)
    }

    private nonisolated static func syncReviews(
        for apps: [AppModel],
        connection: any AppleAccountSyncing,
        storage: PersistentStorable
    ) async -> Int {
        let maxConcurrent = 5
        let reviewsPerApp = 10
        guard !apps.isEmpty else { return 0 }

        var totalSaved = 0
        var index = 0

        await withTaskGroup(of: Int.self) { group in
            func enqueueNext() {
                guard index < apps.count else { return }
                let app = apps[index]
                index += 1
                group.addTask {
                    await fetchAndPersistReviews(
                        for: app,
                        limit: reviewsPerApp,
                        connection: connection,
                        storage: storage
                    )
                }
            }

            for _ in 0..<min(maxConcurrent, apps.count) { enqueueNext() }
            while let saved = await group.next() {
                totalSaved += saved
                enqueueNext()
            }
        }

        return totalSaved
    }

    private nonisolated static func fetchAndPersistReviews(
        for app: AppModel,
        limit: Int,
        connection: any AppleAccountSyncing,
        storage: PersistentStorable
    ) async -> Int {
        do {
            let reviews = try await connection.fetchRecentReviews(appId: app.id, limit: limit)
            var saved = 0
            for var review in reviews {
                review.appId = app.id
                do {
                    try await storage.save(review, id: "review.\(app.id).\(review.id)")
                    saved += 1
                } catch {
                    Log.print.error("[Sync] Save review failed for \(app.name): \(error.localizedDescription)")
                }
            }
            return saved
        } catch {
            Log.print.error("[Sync] Fetch reviews failed for \(app.name): \(error.localizedDescription)")
            return 0
        }
    }

    private nonisolated static func syncPhased(
        for apps: [AppModel],
        versionIdByAppId: [String: String],
        connection: any AppleAccountSyncing,
        storage: PersistentStorable
    ) async -> Int {
        let candidates = apps.filter { app in
            guard let state = app.appStoreState else { return false }
            return state == .pendingDeveloperRelease || state == .readyForSale
        }
        guard !candidates.isEmpty else { return 0 }

        var saved = 0
        await withTaskGroup(of: Bool.self) { group in
            for app in candidates {
                guard let versionId = versionIdByAppId[app.id] else { continue }
                group.addTask {
                    do {
                        if let phased = try await connection.fetchPhasedRelease(versionId: versionId) {
                            try await storage.save(phased, id: "phased.\(app.id)")
                            return true
                        }
                    } catch {
                        Log.print.error("[Sync] Phased release failed for \(app.name): \(error.localizedDescription)")
                    }
                    return false
                }
            }
            while let result = await group.next() {
                if result { saved += 1 }
            }
        }
        return saved
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
