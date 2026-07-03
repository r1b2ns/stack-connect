import Foundation
import WidgetKit
import StackCoreRust
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
            // Validate once up front so the connection seeds `self.provider` before
            // the concurrent `enrichApps` task group runs. Without this, each
            // parallel Swift-only fetch sees a nil provider and lazily re-validates,
            // racing ~1 validate per app (the residual storm from #84). One validate
            // here keeps the count at exactly 1 per account per sync in both flag
            // states. A thrown error is handled by the surrounding catch, which
            // already persists metadata with the error.
            try await connection.validateCredentials()
            let remoteApps = try await connection.syncApps(accountId: account.id, store: SwiftDataBlobStore(storage: storage))
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
            // Self-heal: a fully successful sync proves the agreements are no
            // longer blocking, so clear any previously detected flag.
            await setPendingAgreements(false, storage: storage, accountId: account.id)
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
            if AppleAPIErrorTranslator.isPendingAgreement(error) {
                logAgreementProbe(error, accountName: account.name)
                await setPendingAgreements(true, storage: storage, accountId: account.id)
            }
            // Offline-first contract: a transient/non-agreement error must NOT
            // clear a previously-set flag, so we only clear on a clean sync.
            Log.print.error("[Sync] \(account.name) failed: \(error.localizedDescription)")
            return SyncChange()
        }
    }

    /// Logs the raw 403 fields so we can calibrate the exact ASC agreement code
    /// against a live response (see TODO(#73) in AppleAPIErrorTranslator).
    private nonisolated static func logAgreementProbe(_ error: Error, accountName: String) {
        if case StackCoreRust.StackError.Http(let status, let message) = error {
            let decoded = AppleAPIErrorTranslator.decodeFirstError(fromBody: message)
            let code = decoded?.code ?? "<none>"
            let detail = decoded?.detail ?? "<none>"
            Log.print.error("[Sync][AgreementProbe] \(accountName): status=\(status) code=\(code) detail=\(detail)")
        } else if case StackCoreRust.StackError.PendingAgreements(let message) = error {
            Log.print.error("[Sync][AgreementProbe] \(accountName): \(message)")
        }
    }

    /// Re-fetch-mutate-save the freshest `AccountModel` to flip the pending
    /// agreements flag without clobbering concurrent expirationDate/rules writes.
    /// Only stamps `pendingAgreementsDetectedAt` on a false→true transition so the
    /// original detection time stays stable across re-detections.
    private nonisolated static func setPendingAgreements(
        _ value: Bool,
        storage: PersistentStorable,
        accountId: String
    ) async {
        guard var account: AccountModel = try? await storage.fetch(AccountModel.self, id: accountId) else {
            return
        }
        // Nothing to do if the flag is already in the desired state.
        guard account.hasPendingAgreements != value else { return }

        account.hasPendingAgreements = value
        if value {
            // false→true: stamp the detection time only if not already set.
            if account.pendingAgreementsDetectedAt == nil {
                account.pendingAgreementsDetectedAt = .now
            }
        } else {
            account.pendingAgreementsDetectedAt = nil
        }
        try? await storage.save(account, id: account.id)
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
        let awaitingVersions: [AppPlatformVersion]
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
                                versionString: version.versionString,
                                id: version.id
                            )
                        )
                    }

                    // Every awaiting-eligible version (not deduped to latest-per-platform):
                    // retains a still-phasing readyForSale version even when a newer
                    // version is being prepared, so phased rollouts keep showing.
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
                        appStoreState: latest?.appStoreState,
                        versionString: latest?.versionString,
                        lastModifiedDate: latest?.createdDate,
                        currentVersionId: latest?.id,
                        platform: latest?.platform,
                        platformVersions: platformVersions,
                        awaitingVersions: awaitingVersions
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
                if !e.platformVersions.isEmpty {
                    updated.platformVersions = e.platformVersions
                    updated.awaitingVersions = e.awaitingVersions
                }
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

    /// Fetches phased release data for every awaiting-eligible version and stores
    /// each under `"phased.{versionId}"`. Multi-platform apps (e.g. an iOS and a
    /// tvOS version both phasing) get one entry per platform version, so the
    /// widgets can surface each independently. Apps without per-platform data fall
    /// back to the overall-latest version id from `versionIdByAppId`.
    ///
    /// A phased release is only meaningful once a version is `readyForSale`;
    /// `pendingDeveloperRelease` versions are still fetched because the previous
    /// behavior did, and the API returns `nil` when there is nothing to cache.
    private nonisolated static func syncPhased(
        for apps: [AppModel],
        versionIdByAppId: [String: String],
        connection: any AppleAccountSyncing,
        storage: PersistentStorable
    ) async -> Int {
        // Collect the set of (appName, versionId) pairs to fetch, deduplicated by
        // versionId so we never fetch/store the same version twice.
        var targets: [(appName: String, versionId: String)] = []
        var seenVersionIds = Set<String>()

        for app in apps {
            if let awaitingVersions = app.awaitingVersions {
                // Preferred path: every awaiting-eligible version, including a
                // still-phasing readyForSale version behind a newer prepared one.
                for version in awaitingVersions {
                    guard let versionId = version.id, !seenVersionIds.contains(versionId) else { continue }
                    seenVersionIds.insert(versionId)
                    targets.append((app.name, versionId))
                }
            } else if let platformVersions = app.platformVersions, !platformVersions.isEmpty {
                // Legacy data (pre-awaitingVersions): latest per platform.
                for version in platformVersions where isAwaitingEligible(version.appStoreState) {
                    guard let versionId = version.id, !seenVersionIds.contains(versionId) else { continue }
                    seenVersionIds.insert(versionId)
                    targets.append((app.name, versionId))
                }
            } else if isAwaitingEligible(app.appStoreState) {
                // No per-platform data: fall back to the overall-latest version id.
                guard let versionId = versionIdByAppId[app.id], !seenVersionIds.contains(versionId) else { continue }
                seenVersionIds.insert(versionId)
                targets.append((app.name, versionId))
            }
        }

        guard !targets.isEmpty else { return 0 }

        var saved = 0
        await withTaskGroup(of: Bool.self) { group in
            for target in targets {
                group.addTask {
                    do {
                        if let phased = try await connection.fetchPhasedRelease(versionId: target.versionId) {
                            try await storage.save(phased, id: "phased.\(target.versionId)")
                            return true
                        }
                    } catch {
                        Log.print.error("[Sync] Phased release failed for \(target.appName): \(error.localizedDescription)")
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

    private nonisolated static func isAwaitingEligible(_ state: AppStoreState?) -> Bool {
        state == .pendingDeveloperRelease || state == .readyForSale
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
