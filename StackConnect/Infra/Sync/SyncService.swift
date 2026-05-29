import Foundation
import WidgetKit
#if DEBUG
import UIKit
import UserNotifications
#endif

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
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        // Build the per-account connections on MainActor (Keychain isn't Sendable).
        // The connections themselves are Sendable so they're safe to ship to detached work.
        let prepared: [(AccountModel, (any AppleAccountSyncing)?)] = accounts.map { account in
            let creds: AppleCredentials? = keychain.object(forKey: "credentials.\(account.id)")
            let connection = creds.map(appleConnectionFactory)
            return (account, connection)
        }

        Log.print.notice("[Sync] Starting \(mode == .lightweight ? "lightweight " : "")parallel sync for \(accounts.count) Apple account(s)")
        #if DEBUG
        await postDebugSyncStartedNotification(mode: mode, accountCount: accounts.count)
        #endif
        let storage = self.storage

        let changes = await withTaskGroup(of: SyncChange.self) { group -> SyncChange in
            for (account, connection) in prepared {
                group.addTask { [weak self] in
                    await self?.markInProgress(account.id, started: true)
                    let change = await SyncService.runAccountSync(
                        account: account,
                        connection: connection,
                        storage: storage,
                        mode: mode
                    )
                    await self?.markInProgress(account.id, started: false)
                    return change
                }
            }
            var aggregate = SyncChange()
            for await change in group { aggregate = aggregate + change }
            return aggregate
        }

        state.lastSyncedAt = .now
        state.isSyncing = false
        await preloadWidgetIcons()
        WidgetCenter.shared.reloadAllTimelines()

        // "Fake push": surface status changes and new reviews as local
        // notifications, but only for background (lightweight) syncs — in the
        // foreground the user already sees these updates on screen.
        if mode == .lightweight {
            await LocalNotificationService.scheduleStatusChanges(changes.statusChanges)
            await LocalNotificationService.scheduleNewReviews(changes.newReviews)
        }

        Log.print.notice("[Sync] syncAll completed")
    }

    /// Caches app icons into the shared App Group container so the widget can
    /// render real icons instead of placeholders.
    private func preloadWidgetIcons() async {
        guard let apps: [AppModel] = try? await storage.fetchAll(AppModel.self) else { return }
        let iconURLs = apps.compactMap { $0.iconUrl }
        await WidgetIconCache.preload(iconURLs: iconURLs)
    }

    #if DEBUG
    private func postDebugSyncStartedNotification(mode: SyncMode, accountCount: Int) async {
        // Only surface the "sync started" notification when the app is in the
        // background — a banner while the user is actively using the app is noise.
        guard UIApplication.shared.applicationState == .background else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let allowed: Bool
        switch settings.authorizationStatus {
        case .notDetermined:
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        case .denied:
            allowed = false
        case .authorized, .provisional, .ephemeral:
            allowed = true
        @unknown default:
            allowed = false
        }
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = mode == .lightweight ? "Background sync started" : "Sync started"
        content.body = "Syncing \(accountCount) account\(accountCount == 1 ? "" : "s")"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "sync.started.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
    #endif

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
    ) async -> SyncChange {
        guard let connection else {
            Log.print.error("[Sync] No credentials for \(account.name)")
            await saveMetadata(storage: storage, accountId: account.id, appsSynced: 0, error: "Missing credentials")
            return SyncChange()
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

            var change = SyncChange()

            for app in finalApps {
                do {
                    try await storage.save(app, id: "\(account.id).\(app.id)")
                } catch {
                    Log.print.error("[Sync] Save failed for \(app.name): \(error.localizedDescription)")
                }
            }

            // Detect status transitions vs. the previously cached state. Only
            // apps that had a prior status and genuinely changed count — new apps
            // (and the first sync) are intentionally skipped.
            for app in finalApps where !app.isArchived {
                if let previous = cachedMap[app.id]?.appStoreState,
                   let current = app.appStoreState,
                   previous != current {
                    change.statusChanges.append(
                        SyncChange.StatusChange(
                            accountId: account.id,
                            appId: app.id,
                            appName: app.name,
                            newState: current
                        )
                    )
                }
            }

            let activeApps = finalApps.filter { !$0.isArchived }
            let phasedSaved = await syncPhased(
                for: activeApps,
                versionIdByAppId: versionIdByAppId,
                connection: connection,
                storage: storage
            )

            // Reviews are synced in both modes so the widget's Recent Reviews
            // stays fresh; lightweight (background) fetches fewer per app to stay
            // within the background budget.
            let reviewResult = await syncReviews(
                for: activeApps,
                limit: mode == .lightweight ? 3 : 10,
                connection: connection,
                storage: storage
            )
            change.newReviews = reviewResult.new

            await saveMetadata(
                storage: storage,
                accountId: account.id,
                appsSynced: finalApps.count,
                error: nil
            )
            let modeLabel = mode == .lightweight ? "lightweight" : "full"
            Log.print.notice("[Sync] \(account.name): \(finalApps.count) apps, \(reviewResult.saved) reviews, \(phasedSaved) phased (\(modeLabel))")
            return change
        } catch {
            await saveMetadata(
                storage: storage,
                accountId: account.id,
                appsSynced: 0,
                error: error.localizedDescription
            )
            Log.print.error("[Sync] \(account.name) failed: \(error.localizedDescription)")
            return SyncChange()
        }
    }

    private struct AppEnrichment: Sendable {
        let appId: String
        let iconUrl: String?
        let appStoreState: AppStoreState?
        let versionString: String?
        let lastModifiedDate: Date?
        let currentVersionId: String?
        let platform: AppPlatform?
        let platformVersions: [AppPlatformVersion]
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
                    let versions = (try? await connection.fetchAppStoreVersions(appId: appId, limit: 20)) ?? []
                    // Most recent first, so the overall "latest" and the per-platform
                    // latest both come out correctly.
                    let sorted = versions.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
                    let latest = sorted.first

                    var platformVersions: [AppPlatformVersion] = []
                    var seenPlatforms = Set<String>()
                    for version in sorted {
                        guard let platform = version.platform?.rawValue, !seenPlatforms.contains(platform) else { continue }
                        seenPlatforms.insert(platform)
                        platformVersions.append(
                            AppPlatformVersion(
                                platform: platform,
                                appStoreState: version.appStoreState,
                                versionString: version.versionString
                            )
                        )
                    }

                    let icon = await iconUrl
                    return AppEnrichment(
                        appId: appId,
                        iconUrl: icon,
                        appStoreState: latest?.appStoreState,
                        versionString: latest?.versionString,
                        lastModifiedDate: latest?.createdDate,
                        currentVersionId: latest?.id,
                        platform: latest?.platform,
                        platformVersions: platformVersions
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
                if let platform = e.platform { updated.platform = platform.rawValue }
                if !e.platformVersions.isEmpty { updated.platformVersions = e.platformVersions }
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
        limit reviewsPerApp: Int,
        connection: any AppleAccountSyncing,
        storage: PersistentStorable
    ) async -> (saved: Int, new: [SyncChange.NewReview]) {
        let maxConcurrent = 5
        guard !apps.isEmpty else { return (0, []) }

        var totalSaved = 0
        var allNew: [SyncChange.NewReview] = []
        var index = 0

        await withTaskGroup(of: (Int, [SyncChange.NewReview]).self) { group in
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
            while let result = await group.next() {
                totalSaved += result.0
                allNew.append(contentsOf: result.1)
                enqueueNext()
            }
        }

        return (totalSaved, allNew)
    }

    private nonisolated static func fetchAndPersistReviews(
        for app: AppModel,
        limit: Int,
        connection: any AppleAccountSyncing,
        storage: PersistentStorable
    ) async -> (saved: Int, new: [SyncChange.NewReview]) {
        do {
            let reviews = try await connection.fetchRecentReviews(appId: app.id, limit: limit)
            var saved = 0
            var newReviews: [SyncChange.NewReview] = []
            for var review in reviews {
                review.appId = app.id
                let storageId = "review.\(app.id).\(review.id)"
                // A review is "new" if it wasn't already persisted before this sync.
                let alreadyStored = ((try? await storage.fetch(CustomerReviewModel.self, id: storageId)) ?? nil) != nil
                do {
                    try await storage.save(review, id: storageId)
                    saved += 1
                    if !alreadyStored {
                        newReviews.append(
                            SyncChange.NewReview(
                                accountId: app.accountId,
                                appId: app.id,
                                appName: app.name,
                                reviewId: review.id
                            )
                        )
                    }
                } catch {
                    Log.print.error("[Sync] Save review failed for \(app.name): \(error.localizedDescription)")
                }
            }
            return (saved, newReviews)
        } catch {
            Log.print.error("[Sync] Fetch reviews failed for \(app.name): \(error.localizedDescription)")
            return (0, [])
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
