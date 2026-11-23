import Foundation
import WidgetKit
import StackCoreRust
import StackProtocols
#if DEBUG
import UIKit
import UserNotifications
#endif

// MARK: - State

struct SyncState: Equatable {
    var isSyncing = false
    var accountsInProgress: Set<String> = []
    /// Provider of every account of the running sync, for the "Syncing N
    /// accounts… (2 App Store Connect, 1 Google Play)" banner.
    var providerByAccountId: [String: ProviderType] = [:]
    var lastSyncedAt: Date?
    var lastError: String?
    /// Mode of the running (or last finished) sync; `nil` before the first run.
    var lastRunMode: SyncMode?
    /// Accounts the running (or last finished) sync covered.
    var lastRunAccountCount = 0
    /// Accounts whose leg failed in the last finished sync. `lastError` only
    /// reports run-level failures (e.g. the accounts can't be loaded).
    var lastRunFailedAccountCount = 0

    /// The last run finished with every account synced and no error at all.
    var lastRunSucceeded: Bool {
        !isSyncing && lastError == nil && lastRunFailedAccountCount == 0
    }

    /// Accounts still syncing, per provider.
    var inProgressCountByProvider: [ProviderType: Int] {
        var counts: [ProviderType: Int] = [:]
        for accountId in accountsInProgress {
            if let provider = providerByAccountId[accountId] {
                counts[provider, default: 0] += 1
            }
        }
        return counts
    }
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
    typealias GooglePlayConnectionFactory = (GooglePlayCredentials) -> any GooglePlaySyncConnecting
    /// Rewrites the WidgetKit snapshot and reloads the timelines (plan H6).
    typealias WidgetSnapshotWriting = @MainActor (PersistentStorable) async -> Void

    static let shared = SyncService()

    @Published private(set) var state = SyncState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let appleConnectionFactory: AppleConnectionFactory
    private let googlePlayConnectionFactory: GooglePlayConnectionFactory
    private let widgetSnapshotWriter: WidgetSnapshotWriting
    private let firstAppsLoaded: FirstAppsLoadedTracker
    private let analytics: AnalyticsTracking
    private let notificationPermission: NotificationPermissionRequesting
    /// Accounts of a hidden store (Google Play while `googlePlayAccounts` is
    /// OFF) are not synced: no request, no notification, no widget row.
    private let featureFlags: FeatureFlags
    private let clock = ContinuousClock()
    private var rootTask: Task<Void, Never>?

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        appleConnectionFactory: AppleConnectionFactory? = nil,
        googlePlayConnectionFactory: GooglePlayConnectionFactory? = nil,
        widgetSnapshotWriter: WidgetSnapshotWriting? = nil,
        firstAppsLoaded: FirstAppsLoadedTracker? = nil,
        analytics: AnalyticsTracking? = nil,
        notificationPermission: NotificationPermissionRequesting? = nil,
        featureFlags: FeatureFlags = .shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.appleConnectionFactory = appleConnectionFactory ?? { AppleAccountConnection(credentials: $0) }
        self.googlePlayConnectionFactory = googlePlayConnectionFactory ?? { GooglePlayAccountConnection(credentials: $0) }
        self.widgetSnapshotWriter = widgetSnapshotWriter ?? { await WidgetDashboardSnapshotWriter.write(storage: $0) }
        self.firstAppsLoaded = firstAppsLoaded ?? .shared
        self.analytics = analytics ?? AnalyticsService.shared
        self.notificationPermission = notificationPermission ?? NotificationPermissionService.shared
        self.featureFlags = featureFlags
    }

    /// One account of a sync run with the connection built for it (`nil` when
    /// its credentials are missing).
    private enum PreparedAccount: @unchecked Sendable {
        case apple(AccountModel, (any AppleAccountSyncing)?)
        case googlePlay(AccountModel, (any GooglePlaySyncConnecting)?)

        var account: AccountModel {
            switch self {
            case .apple(let account, _), .googlePlay(let account, _): return account
            }
        }
    }

    /// Fire-and-forget. Safe to call repeatedly — already-running syncs are coalesced
    /// (subsequent callers receive the same in-flight Task and can await it if needed).
    ///
    /// Each run (not a coalesced call) is tracked as a `sync` action with its
    /// `trigger`, on `screen` (`nil` for the background task).
    ///
    /// - Parameters:
    ///   - trigger: what asked for the run. Defaults to `background` for a
    ///     lightweight run, `foreground` otherwise.
    ///   - screen: the screen that asked for it, if any.
    @discardableResult
    func syncAll(mode: SyncMode = .full, trigger: SyncTrigger? = nil, screen: AnalyticsScreen? = .home) -> Task<Void, Never> {
        if let rootTask {
            Log.print.info("[Sync] syncAll coalesced into in-flight sync")
            return rootTask
        }
        let trigger = trigger ?? (mode == .lightweight ? .background : .foreground)
        let task = Task { [weak self] in
            await self?.performSyncAll(mode: mode, trigger: trigger, screen: screen)
            self?.rootTask = nil
        }
        rootTask = task
        return task
    }

    // MARK: - Private (MainActor)

    private func performSyncAll(mode: SyncMode, trigger: SyncTrigger, screen: AnalyticsScreen?) async {
        let startedAt = clock.now
        let outcome = await runSyncAll(mode: mode)
        trackSync(outcome, trigger: trigger, screen: screen, duration: clock.now - startedAt)
    }

    /// What a run did, for its `sync` analytics event.
    struct RunOutcome: Equatable {
        var accountCount = 0
        var failedCount = 0
        /// Set when the run failed as a whole or any account leg failed.
        var errorCategory: AnalyticsErrorCategory?

        var succeeded: Bool { errorCategory == nil && failedCount == 0 }
    }

    /// The `sync` action of a finished run (pure, unit tested).
    static func syncEvent(
        _ outcome: RunOutcome,
        trigger: SyncTrigger,
        screen: AnalyticsScreen?,
        duration: Duration
    ) -> AnalyticsEvent {
        var parameters: [String: AnalyticsValue] = [
            AnalyticsParameterKey.trigger: .string(trigger.rawValue),
            AnalyticsParameterKey.durationBucket: .string(AnalyticsDurationBucket(duration: duration).rawValue),
            AnalyticsParameterKey.count: .int(outcome.accountCount),
            AnalyticsParameterKey.failedCount: .int(outcome.failedCount)
        ]
        if let category = outcome.errorCategory {
            parameters.merge(category.parameters) { _, new in new }
        }
        return .action(.sync, on: screen, result: outcome.succeeded ? .success : .failure, parameters: parameters)
    }

    private func trackSync(_ outcome: RunOutcome, trigger: SyncTrigger, screen: AnalyticsScreen?, duration: Duration) {
        analytics.track(Self.syncEvent(outcome, trigger: trigger, screen: screen, duration: duration))
    }

    private func runSyncAll(mode: SyncMode) async -> RunOutcome {
        var started = state
        started.isSyncing = true
        started.lastError = nil
        started.lastRunMode = mode
        started.lastRunAccountCount = 0
        started.lastRunFailedAccountCount = 0
        state = started

        let accounts: [AccountModel]
        do {
            // Firebase has nothing to sync in the background.
            let all: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            accounts = featureFlags.visibleAccounts(all).filter { $0.providerType == .apple || $0.providerType == .googlePlay }
        } catch {
            state.lastError = error.localizedDescription
            state.isSyncing = false
            Log.print.error("[Sync] Failed to load accounts: \(error.localizedDescription)")
            return RunOutcome(errorCategory: .storage)
        }

        guard !accounts.isEmpty else {
            state.isSyncing = false
            state.lastSyncedAt = .now
            await widgetSnapshotWriter(storage)
            return RunOutcome()
        }

        // Build the per-account connections on MainActor (Keychain isn't Sendable).
        // The connections themselves are Sendable so they're safe to ship to detached work.
        let prepared: [PreparedAccount] = accounts.map { account in
            let key = "credentials.\(account.id)"
            switch account.providerType {
            case .googlePlay:
                let creds: GooglePlayCredentials? = keychain.object(forKey: key)
                return .googlePlay(account, creds.map(googlePlayConnectionFactory))
            default:
                let creds: AppleCredentials? = keychain.object(forKey: key)
                return .apple(account, creds.map(appleConnectionFactory))
            }
        }
        state.lastRunAccountCount = accounts.count
        state.providerByAccountId = Dictionary(accounts.map { ($0.id, $0.providerType) }, uniquingKeysWith: { first, _ in first })

        let playCount = accounts.filter { $0.providerType == .googlePlay }.count
        Log.print.notice("[Sync] Starting \(mode == .lightweight ? "lightweight " : "")parallel sync for \(accounts.count - playCount) Apple and \(playCount) Google Play account(s)")
        #if DEBUG
        await postDebugSyncStartedNotification(mode: mode, accountCount: accounts.count)
        #endif
        let storage = self.storage

        let changes = await withTaskGroup(of: SyncChange.self) { group -> SyncChange in
            for item in prepared {
                let accountId = item.account.id
                group.addTask { [weak self] in
                    await self?.markInProgress(accountId, started: true)
                    let change: SyncChange
                    switch item {
                    case let .apple(account, connection):
                        change = await SyncService.runAccountSync(
                            account: account,
                            connection: connection,
                            storage: storage,
                            mode: mode
                        )
                    case let .googlePlay(account, connection):
                        change = await SyncService.runGooglePlaySync(
                            account: account,
                            connection: connection,
                            storage: storage,
                            mode: mode
                        )
                    }
                    await self?.markInProgress(accountId, started: false)
                    return change
                }
            }
            var aggregate = SyncChange()
            for await change in group { aggregate = aggregate + change }
            return aggregate
        }

        // One mutation, so observers see the failure count together with the
        // end of the run (the review prompt reacts to this transition).
        var finished = state
        finished.lastRunFailedAccountCount = changes.failedAccountIds.count
        finished.lastSyncedAt = .now
        finished.isSyncing = false
        state = finished
        // Activation milestone: the first leg that brought at least one app.
        if let first = changes.loadedApps.first(where: { $0.count > 0 }) {
            await firstAppsLoaded.recordAppsLoaded(count: first.count, provider: first.provider, on: .home)
        }
        await preloadWidgetIcons()
        await widgetSnapshotWriter(storage)

        // "Fake push": surface status changes and new reviews as local
        // notifications, but only for background (lightweight) syncs — in the
        // foreground the user already sees these updates on screen.
        if mode == .lightweight {
            await LocalNotificationService.scheduleStatusChanges(changes.statusChanges)
            await LocalNotificationService.scheduleNewReviews(changes.newReviews)
        }

        Log.print.notice("[Sync] syncAll completed")
        return RunOutcome(
            accountCount: accounts.count,
            failedCount: changes.failedAccountIds.count,
            errorCategory: changes.dominantFailureCategory
        )
    }

    /// Caches app icons into the shared App Group container so the widget can
    /// render real icons instead of placeholders.
    private func preloadWidgetIcons() async {
        let apps: [AppModel] = (try? await storage.fetchAll(AppModel.self)) ?? []
        // Include per-platform icons so the WidgetKit extension (which can't fetch
        // at render time) has the bytes cached for each awaiting platform's row.
        // `WidgetIconCache.preload` dedups via a Set.
        var iconURLs = apps.flatMap { app -> [String] in
            var urls: [String] = []
            if let icon = app.iconUrl { urls.append(icon) }
            for version in (app.platformVersions ?? []) + (app.awaitingVersions ?? []) {
                if let icon = version.iconUrl { urls.append(icon) }
            }
            return urls
        }
        // Google Play apps live in one cached list per account (none while
        // Google Play is hidden).
        let playLists: [[GooglePlayAppItem]] = featureFlags.isProviderAvailable(.googlePlay)
            ? ((try? await storage.fetchAll([GooglePlayAppItem].self)) ?? [])
            : []
        iconURLs += playLists.flatMap { $0.compactMap(\.iconUrl) }
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
            // Through the tracked prompt: its answer and `notifications_enabled`.
            allowed = await notificationPermission.requestAuthorization(options: [.alert, .sound])
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

    private nonisolated static func runGooglePlaySync(
        account: AccountModel,
        connection: (any GooglePlaySyncConnecting)?,
        storage: PersistentStorable,
        mode: SyncMode
    ) async -> SyncChange {
        guard let connection else {
            Log.print.error("[Sync] No credentials for \(account.name)")
            await saveMetadata(storage: storage, accountId: account.id, appsSynced: 0, error: "Missing credentials")
            return .failed(accountId: account.id, category: .invalidCredentials)
        }
        return await GooglePlayAccountSync(account: account, connection: connection, storage: storage, mode: mode).run()
    }

    private nonisolated static func runAccountSync(
        account: AccountModel,
        connection: (any AppleAccountSyncing)?,
        storage: PersistentStorable,
        mode: SyncMode
    ) async -> SyncChange {
        guard let connection else {
            Log.print.error("[Sync] No credentials for \(account.name)")
            await saveMetadata(storage: storage, accountId: account.id, appsSynced: 0, error: "Missing credentials")
            return .failed(accountId: account.id, category: .invalidCredentials)
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
            let fetchedApps = try await connection.syncApps(accountId: account.id, store: SwiftDataBlobStore(storage: storage))
            // Per-app export scope: for imported accounts restricted to a subset,
            // excluded apps are never derived, enriched, or persisted (nil/empty
            // ⇒ allowsApp returns true, so unrestricted accounts pay ~zero cost).
            let remoteApps = fetchedApps.filter { account.allowsApp(bundleId: $0.bundleId) }
            let allCached: [AppModel] = (try? await storage.fetchAll(AppModel.self)) ?? []

            // Purge already-persisted rows that are now excluded (covers a
            // re-import or a tightened scope), cascading their versions/reviews.
            await purgeExcludedApps(
                account: account,
                cachedApps: allCached.filter { $0.accountId == account.id },
                storage: storage
            )

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
                            status: SyncChange.StatusLabel(appStore: current)
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
            change.loadedApps = [SyncChange.LoadedApps(provider: account.providerType, count: finalApps.count)]

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
            return .failed(accountId: account.id, category: AnalyticsErrorCategory(connectionError: error))
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

    /// Deletes cached `AppModel` rows (and their versions/reviews) that the
    /// account's per-app export scope no longer allows. No-op for unrestricted
    /// accounts (`allowsApp` returns true for every bundleId). Mirrors the
    /// cascade idiom in `SettingsAccountsViewModel.deleteAccount`.
    private nonisolated static func purgeExcludedApps(
        account: AccountModel,
        cachedApps: [AppModel],
        storage: PersistentStorable
    ) async {
        let excluded = cachedApps.filter { !account.allowsApp(bundleId: $0.bundleId) }
        guard !excluded.isEmpty else { return }

        let allVersions: [AppStoreVersionModel] = (try? await storage.fetchAll(AppStoreVersionModel.self)) ?? []
        let allReviews: [CustomerReviewModel] = (try? await storage.fetchAll(CustomerReviewModel.self)) ?? []

        for app in excluded {
            for version in allVersions where version.appId == app.id {
                try? await storage.delete(AppStoreVersionModel.self, id: "version.\(version.id)")
            }
            for review in allReviews where review.appId == app.id {
                try? await storage.delete(CustomerReviewModel.self, id: "review.\(app.id).\(review.id)")
            }
            try? await storage.delete(AppModel.self, id: "\(account.id).\(app.id)")
        }
        Log.print.notice("[Sync] \(account.name): purged \(excluded.count) apps excluded by per-app scope")
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

                    // Per-platform icons: a single `app.iconUrl` only represents one
                    // target, so multi-platform apps resolve each platform's real icon
                    // from its most-recent build. Bounded to multi-platform apps
                    // (single-platform apps' per-platform icon equals the app icon) and
                    // best-effort so a builds failure never aborts enrichment.
                    let distinctPlatforms = Set(sorted.compactMap { $0.platform })
                    var platformIcons: [AppPlatform: String] = [:]
                    if distinctPlatforms.count > 1 {
                        let builds = (try? await connection.fetchBuilds(appId: appId, limit: 50)) ?? []
                        platformIcons = PlatformIconResolver.icons(from: builds)
                    }

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
                                id: version.id,
                                iconUrl: version.platform.flatMap { platformIcons[$0] }
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
                            id: version.id,
                            iconUrl: version.platform.flatMap { platformIcons[$0] }
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
