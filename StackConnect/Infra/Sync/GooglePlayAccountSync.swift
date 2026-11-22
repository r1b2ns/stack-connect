import Foundation

/// Everything the background sync reads from one Google Play account: the app
/// listing, the public icon lookup, the release summaries and the first page of
/// reviews. Deliberately **no** edit-based seam (app details, listings, tracks,
/// bundles, writes): a background read must never open a Play edit, which would
/// cancel an edit the same service account has open elsewhere, e.g. a CI upload
/// (plan D14, H2).
typealias GooglePlaySyncConnecting = GooglePlayAppListConnecting & GooglePlayReviewsConnecting

/// Where the lightweight (background) sync resumes reading reviews for one Play
/// account (plan H5). Stored under `storageId(accountId:)`, removed by
/// `AccountCascadeDeleter`.
struct GooglePlayReviewRotation: Codable, Hashable, Sendable {
    let accountId: String
    /// Index (in package-name order) of the first app the next run reads.
    var nextIndex: Int

    static func storageId(accountId: String) -> String {
        "googleplay-review-rotation.\(accountId)"
    }

    /// The next `limit` packages starting at `cursor`, wrapping around, and the
    /// cursor of the run after. Everything fits in one run when there are at
    /// most `limit` packages (the cursor then stays at 0).
    static func batch(_ packages: [String], cursor: Int, limit: Int) -> (batch: [String], nextCursor: Int) {
        guard !packages.isEmpty, limit > 0 else { return ([], 0) }
        guard packages.count > limit else { return (packages, 0) }
        let start = ((cursor % packages.count) + packages.count) % packages.count
        let batch = (0..<limit).map { packages[(start + $0) % packages.count] }
        return (batch, (start + limit) % packages.count)
    }
}

/// The Google Play leg of `SyncService` (plan S1): refreshes one account's app
/// list, missing icons, release summaries and recent reviews, never opening an
/// edit.
///
/// - Apps: same merge as the Play app list (`GooglePlayAppListSync.merge`), only
///   apps in the account's per-app scope, saved to `googleplay-apps.{accountId}`.
/// - Icons: public store page, at most `maxConcurrentIconFetches` at once.
/// - Release summaries (`canView(.version)` only): an automatic
///   `GooglePlayReleaseSummariesRefresher` run — nothing during a Google Play
///   quota cooldown, apps refreshed in the last minutes skipped, only the
///   tracks known to hold a release, stopped at the first quota hit, at most
///   `maxConcurrentSummaryFetches` at once; an app's `googleplay-releases.*`
///   entry is replaced only when every track asked answered. Lifecycle changes
///   become `SyncChange.StatusChange`s (H8).
/// - Reviews (`canView(.review)` only): the first page per app, saved as
///   `CustomerReviewModel` under `review.{packageName}.{reviewId}` next to the
///   App Store ones (plan H4). Full sync reads every app, at most
///   `maxConcurrentReviewFetches` at once; lightweight sync reads at most
///   `lightweightReviewAppLimit` apps per run, rotating through the rest on
///   later runs, to stay well under Google's review quota (plan H5).
struct GooglePlayAccountSync: Sendable {

    static let maxConcurrentIconFetches = 4
    static let maxConcurrentSummaryFetches = GooglePlayReleaseSummariesRefresher.maxConcurrentFetches
    static let maxConcurrentReviewFetches = 5
    static let lightweightReviewAppLimit = 20

    let account: AccountModel
    let connection: any GooglePlaySyncConnecting
    let storage: PersistentStorable
    let mode: SyncMode
    /// Clock of the release-summary intervals and quota cooldown. Injected for tests.
    let now: @Sendable () -> Date

    init(
        account: AccountModel,
        connection: any GooglePlaySyncConnecting,
        storage: PersistentStorable,
        mode: SyncMode,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        var account = account
        account.fillMissingRules()
        self.account = account
        self.connection = connection
        self.storage = storage
        self.mode = mode
        self.now = now
    }

    /// Runs the whole leg. A failed app listing fails the account (recorded in
    /// its `SyncMetadata`) and keeps every cache as it was.
    func run() async -> SyncChange {
        let cached = (try? await storage.fetch([GooglePlayAppItem].self, id: listKey)) ?? []
        let remote: [GooglePlayAppItem]
        do {
            let fetched = try await connection.fetchApps().filter { account.allowsApp(bundleId: $0.bundleId) }
            remote = GooglePlayAppListSync.merge(remote: fetched, into: cached.filter(isInScope))
        } catch {
            Log.print.error("[Sync][GooglePlay] \(account.name) failed: \(error.localizedDescription)")
            await saveMetadata(appsSynced: 0, error: error.userFacingMessage)
            return .failed(accountId: account.id, category: AnalyticsErrorCategory(connectionError: error))
        }

        var apps = remote
        let icons = await GooglePlayAppListSync.fetchIcons(
            packageNames: apps.filter { $0.iconUrl == nil }.map(\.packageName),
            using: connection,
            maxConcurrent: Self.maxConcurrentIconFetches
        )
        for index in apps.indices where apps[index].iconUrl == nil {
            apps[index].iconUrl = icons[apps[index].packageName]
        }
        do {
            try await storage.save(apps, id: listKey)
        } catch {
            Log.print.error("[Sync][GooglePlay] Saving the app list failed for \(account.name): \(error.localizedDescription)")
        }

        var change = SyncChange()
        // Archived apps are kept (and persisted above) but skip the expensive
        // per-app calls, like the App Store leg (`SyncService`).
        let activeApps = apps.filter { !$0.isArchived }
        if account.canView(.version) {
            change.statusChanges = await syncReleaseSummaries(for: activeApps)
        }
        var reviewsSaved = 0
        if account.canView(.review) {
            let result = await syncReviews(for: activeApps)
            change.newReviews = result.new
            reviewsSaved = result.saved
        }

        change.loadedApps = [SyncChange.LoadedApps(provider: .googlePlay, count: apps.count)]
        await saveMetadata(appsSynced: apps.count, error: nil)
        let modeLabel = mode == .lightweight ? "lightweight" : "full"
        Log.print.notice("[Sync][GooglePlay] \(account.name): \(apps.count) apps, \(reviewsSaved) reviews (\(modeLabel))")
        return change
    }

    // MARK: - Release summaries

    /// Fetches and caches the summaries of the apps due a refresh (an automatic
    /// run shared with the Play app list, see
    /// `GooglePlayReleaseSummariesRefresher`); returns the releases
    /// whose lifecycle state changed since the previous cache (new releases and
    /// the first sync are skipped, like App Store status changes, plan H8).
    private func syncReleaseSummaries(for apps: [GooglePlayAppItem]) async -> [SyncChange.StatusChange] {
        let refresher = GooglePlayReleaseSummariesRefresher(
            accountId: account.id,
            storage: storage,
            fetcher: connection,
            maxConcurrent: Self.maxConcurrentSummaryFetches,
            logTag: "Sync][GooglePlay",
            now: now
        )
        // The refresher saves the entries (also when this leg shares a run the
        // Play app list started) and hands back the ones they replaced.
        let outcome = await refresher.refresh(packages: apps.map(\.packageName), trigger: .automatic)

        var changes: [SyncChange.StatusChange] = []
        for app in apps {
            guard let entry = outcome.entries[app.packageName],
                  let previous = outcome.previousEntries[app.packageName] else { continue }
            changes += Self.statusChanges(from: previous.summaries, to: entry.summaries, app: app, accountId: account.id)
        }
        return changes
    }

    /// Releases (by track + version codes) present in both lists whose
    /// lifecycle state differs.
    static func statusChanges(
        from previous: [GooglePlayReleaseSummaryModel],
        to current: [GooglePlayReleaseSummaryModel],
        app: GooglePlayAppItem,
        accountId: String
    ) -> [SyncChange.StatusChange] {
        let before = Dictionary(previous.map { ($0.releaseKey, $0.lifecycleState) }, uniquingKeysWith: { first, _ in first })
        return current.compactMap { summary in
            guard let old = before[summary.releaseKey], old != summary.lifecycleState else { return nil }
            return SyncChange.StatusChange(
                accountId: accountId,
                appId: app.packageName,
                appName: app.displayName,
                status: SyncChange.StatusLabel(googlePlay: summary)
            )
        }
    }

    // MARK: - Reviews

    private func syncReviews(for apps: [GooglePlayAppItem]) async -> (saved: Int, new: [SyncChange.NewReview]) {
        let ordered = apps.sorted { $0.packageName < $1.packageName }
        let selected: [GooglePlayAppItem]
        switch mode {
        case .full:
            selected = ordered
        case .lightweight:
            let rotationId = GooglePlayReviewRotation.storageId(accountId: account.id)
            let cursor = (try? await storage.fetch(GooglePlayReviewRotation.self, id: rotationId))?.nextIndex ?? 0
            let (batch, next) = GooglePlayReviewRotation.batch(
                ordered.map(\.packageName), cursor: cursor, limit: Self.lightweightReviewAppLimit
            )
            let byPackage = Dictionary(ordered.map { ($0.packageName, $0) }, uniquingKeysWith: { first, _ in first })
            selected = batch.compactMap { byPackage[$0] }
            try? await storage.save(GooglePlayReviewRotation(accountId: account.id, nextIndex: next), id: rotationId)
        }
        guard !selected.isEmpty else { return (0, []) }

        let limit = mode == .lightweight ? 3 : 10
        var saved = 0
        var newReviews: [SyncChange.NewReview] = []
        var pending = selected[...]
        await withTaskGroup(of: (Int, [SyncChange.NewReview]).self) { group in
            func schedule(_ app: GooglePlayAppItem) {
                group.addTask { await fetchAndPersistReviews(for: app, limit: limit) }
            }
            for _ in 0..<Self.maxConcurrentReviewFetches {
                guard let app = pending.popFirst() else { break }
                schedule(app)
            }
            for await (count, new) in group {
                saved += count
                newReviews += new
                if let app = pending.popFirst() { schedule(app) }
            }
        }
        return (saved, newReviews)
    }

    private func fetchAndPersistReviews(for app: GooglePlayAppItem, limit: Int) async -> (Int, [SyncChange.NewReview]) {
        do {
            let page = try await connection.fetchCustomerReviewsPage(
                packageName: app.packageName, filterRating: nil, limit: limit, pageToken: nil
            )
            var saved = 0
            var new: [SyncChange.NewReview] = []
            for var review in page.reviews {
                review.appId = app.packageName
                let storageId = CustomerReviewModel.storageId(appId: app.packageName, reviewId: review.id)
                let alreadyStored = ((try? await storage.fetch(CustomerReviewModel.self, id: storageId)) ?? nil) != nil
                do {
                    try await storage.save(review, id: storageId)
                    saved += 1
                    if !alreadyStored {
                        new.append(SyncChange.NewReview(
                            accountId: account.id, appId: app.packageName, appName: app.displayName, reviewId: review.id
                        ))
                    }
                } catch {
                    Log.print.error("[Sync][GooglePlay] Save review failed for \(app.packageName): \(error.localizedDescription)")
                }
            }
            return (saved, new)
        } catch {
            Log.print.error("[Sync][GooglePlay] Fetch reviews failed for \(app.packageName): \(error.localizedDescription)")
            return (0, [])
        }
    }

    // MARK: - Helpers

    private var listKey: String {
        GooglePlayAppItem.cacheKey(accountId: account.id)
    }

    private func isInScope(_ app: GooglePlayAppItem) -> Bool {
        account.allowsApp(bundleId: app.packageName)
    }

    private func saveMetadata(appsSynced: Int, error: String?) async {
        let metadata = SyncMetadata(accountId: account.id, lastSyncedAt: .now, lastError: error, appsSynced: appsSynced)
        try? await storage.save(metadata, id: "sync.account.\(account.id)")
    }
}
