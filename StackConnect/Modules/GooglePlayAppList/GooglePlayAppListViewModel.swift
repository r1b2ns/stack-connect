import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol GooglePlayAppListViewModelProtocol: ObservableObject {
    var uiState: GooglePlayAppListUiState { get set }
    func load() async
    func refresh() async
    func addApp(packageName: String) async
    func removeApp(_ app: GooglePlayAppItem) async
}

// MARK: - UiState

struct GooglePlayAppListUiState {
    var account: AccountModel
    var apps: [GooglePlayAppItem] = []
    var isLoading = false
    var isSyncing = false
    var showSyncToast = false
    /// Last load/sync failure, already user-facing. Shown full screen when there is
    /// nothing cached, or as an inline banner above the cached list.
    var error: String?
    var showAddApp = false
    var isAdding = false
    var addError: String?
    var toastMessage: ToastMessage?
    /// Search field text: matches the app name or package name.
    var searchQuery = ""
    /// Release status lines per package name (one per track with a release),
    /// from the release summaries cache. Empty without `canViewReleases`.
    var releaseStatus: [String: [GooglePlayTrackStatusLine]] = [:]
    /// End of the Google Play quota cooldown that pauses the release status
    /// refreshes (`GooglePlayQuotaCooldown`), `nil` when none is in force.
    var releaseStatusPausedUntil: Date?

    /// Release status is gated by the account's `version` rule (plan R5).
    var canViewReleases: Bool {
        account.canView(.version)
    }

    /// The list's footer note while a quota cooldown pauses the release status
    /// ("… Retrying after 14:35."), `nil` otherwise. Never an alert: the
    /// cached status stays on screen.
    var releaseStatusPausedNote: String? {
        guard canViewReleases, let until = releaseStatusPausedUntil else { return nil }
        let time = until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated, time: .shortened)
        return String(localized: "Release status paused: Google Play API quota reached. Retrying after \(time).",
                      comment: "Google Play app list footer while Google's API quota pauses the release status. Argument: when it is retried, e.g. 14:35.")
    }

    /// `apps` narrowed by `searchQuery` (name or package, case-insensitive).
    var filteredApps: [GooglePlayAppItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.packageName.localizedCaseInsensitiveContains(query)
        }
    }

    /// Manual "add app by package name" is allowed by the account's rules.
    var canAddApps: Bool {
        account.canAdd(.apps)
    }

    /// Removing a manually added app is allowed by the account's rules.
    var canDeleteApps: Bool {
        account.canDelete(.apps)
    }

    /// Footer of the "add app by package name" sheet: who needs access to it.
    var addAppFooter: String {
        switch account.authMethod {
        case .keyFile:
            return String(localized: "Enter the Android package name (e.g. com.example.myapp). The service account must have access to this app in the Google Play Console.")
        case .googleSignIn:
            return String(localized: "Enter the Android package name (e.g. com.example.myapp). The signed-in Google account must have access to this app in the Google Play Console.")
        }
    }
}

/// One line of a Play app row: the headline release of one track
/// ("Production · In review (4.2.0)").
struct GooglePlayTrackStatusLine: Hashable, Identifiable {
    let track: String
    let lifecycleState: GooglePlayReleaseLifecycleState
    /// The release's short name (version name), `nil` when it has none.
    let versionName: String?

    var id: String { track }

    var trackKind: GooglePlayTrackKind {
        GooglePlayTrackKind(track: track)
    }

    /// "Production · In review".
    var text: String {
        String(localized: "\(trackKind.displayName) · \(lifecycleState.displayName)",
               comment: "Google Play app list status line: track name, then the release lifecycle state.")
    }

    /// One line per track that has a release, production first.
    static func lines(from cache: GooglePlayReleaseSummariesCache) -> [GooglePlayTrackStatusLine] {
        cache.tracks.compactMap { entry in
            guard let headline = GooglePlayReleaseSummaryModel.headline(of: entry.releases) else { return nil }
            return GooglePlayTrackStatusLine(
                track: entry.track,
                lifecycleState: headline.lifecycleState,
                versionName: headline.name == nil ? nil : headline.shortName
            )
        }
    }
}

// MARK: - Implementation

@MainActor
final class GooglePlayAppListViewModel: GooglePlayAppListViewModelProtocol {

    /// Builds the Rust-core connection for the stored credentials (app listing +
    /// public icon lookup). Injected so tests never touch the network or the core.
    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayAppListConnecting

    /// Builds the manual-add access check (Rust core `fetchAppDetails`). Injected for tests.
    typealias AccessCheckerFactory = (GooglePlayCredentials) -> any GooglePlayAppAccessChecking

    /// Icon lookups in flight at once. Each one downloads a public store page,
    /// so a large account fills its icons in a few rounds instead of firing a
    /// request per app at once.
    static let maxConcurrentIconFetches = 4

    /// Release summary requests (one per app and track) in flight at once:
    /// Google counts its quota per minute.
    static let maxConcurrentSummaryFetches = GooglePlayReleaseSummariesRefresher.maxConcurrentFetches

    /// Tracks every app is asked for (see `GooglePlayAppListSync.standardTracks`).
    static var standardTracks: [String] { GooglePlayAppListSync.standardTracks }

    @Published var uiState: GooglePlayAppListUiState

    private let keychain: KeyStorable
    private let storage: PersistentStorable
    private let connectionFactory: ConnectionFactory
    private let accessCheckerFactory: AccessCheckerFactory
    private let connectivity: ConnectivityProviding
    /// Clock of the release-summary intervals and quota cooldown. Injected for tests.
    private let now: @Sendable () -> Date

    /// Package names whose icon is being looked up, so overlapping passes (a pull
    /// to refresh during the first load, a manual add) never ask twice.
    private var iconFetchesInFlight = Set<String>()

    /// Package names whose release summaries are being fetched (same guard as
    /// the icons: overlapping passes never ask twice).
    private var summaryFetchesInFlight = Set<String>()
    private let analytics: AnalyticsTracking
    private let firstAppsLoaded: FirstAppsLoadedTracker

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) },
        accessCheckerFactory: @escaping AccessCheckerFactory = {
            GooglePlayCoreAccessChecker(appDetails: GooglePlayAccountConnection(credentials: $0))
        },
        connectivity: ConnectivityProviding = ConnectivityMonitor.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        firstAppsLoaded: FirstAppsLoadedTracker = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.uiState = GooglePlayAppListUiState(account: account)
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
        self.connectionFactory = connectionFactory
        self.accessCheckerFactory = accessCheckerFactory
        self.connectivity = connectivity
        self.analytics = analytics
        self.firstAppsLoaded = firstAppsLoaded
        self.now = now
    }

    // MARK: - Load

    /// Offline-first: shows the cached list right away, then syncs it from the
    /// Play Developer Reporting API (via the Rust core) and persists the result.
    /// A failed sync keeps whatever is on screen. Then, unless offline, fills in
    /// missing icons (`fetchMissingIcons`) — after the list is on screen, so
    /// icons never hold it back. Like the App Store list, `isSyncing` covers the
    /// whole network pass (icons included); the sync toast is time-boxed, so the
    /// icon pass can't keep it up.
    ///
    /// Per-app scope of an imported account (`AccountModel.allowsApp`, nil/empty
    /// ⇒ every app): apps outside it are never shown nor persisted — mirroring
    /// the App Store `AppListViewModel`.
    func load() async {
        await performLoad(trigger: .automatic)
    }

    /// Pull-to-refresh: same load, tracked as a `refresh` action with its
    /// outcome. The release status is asked for every app and track, even
    /// during a quota cooldown (once; a new hit extends it).
    func refresh() async {
        await performLoad(trigger: .userRefresh)
        analytics.track(.action(.refresh, on: .googlePlayAppList, result: uiState.error == nil ? .success : .failure))
    }

    private func performLoad(trigger: GooglePlayReleaseSummariesRefresher.Trigger) async {
        uiState.error = nil

        // 1. Cached list first (offline-first). Defense-in-depth: hide any cached
        //    row outside the scope (the next save drops it from the cache).
        if let cached = await loadFromStorage()?.filter(isInScope), !cached.isEmpty {
            uiState.apps = Self.sorted(cached)
        }
        await loadCachedReleaseStatus()
        uiState.isLoading = uiState.apps.isEmpty

        guard let credentials = storedCredentials() else {
            Log.print.error("[GooglePlayAppList] No credentials found for account: \(self.uiState.account.name)")
            uiState.error = String(localized: "No credentials found for this account.")
            uiState.isLoading = false
            return
        }

        // 2. Sync from the API.
        uiState.isSyncing = true
        if !uiState.apps.isEmpty {
            uiState.showSyncToast = true
        }

        // One connection (one core provider) for the listing and the icons.
        let connection = connectionFactory(credentials)
        var syncFailedOffline = false
        var syncedAppCount: Int?

        do {
            let remoteApps = try await connection.fetchApps().filter {
                self.uiState.account.allowsApp(bundleId: $0.bundleId)
            }
            uiState.apps = Self.merge(remote: remoteApps, into: uiState.apps)
            await saveToStorage()
            // Apps new to the list may already have a cached status.
            await loadCachedReleaseStatus()
            Log.print.info("[GooglePlayAppList] Synced \(remoteApps.count) apps for account: \(self.uiState.account.name)")
            syncedAppCount = uiState.apps.count
        } catch {
            Log.print.error("[GooglePlayAppList] Sync failed: \(error.localizedDescription)")
            syncFailedOffline = GooglePlayErrorTranslator.isOffline(error)
            // Offline with a cached list: the global offline banner already says
            // so — keep the list without a second warning.
            if !(syncFailedOffline && !uiState.apps.isEmpty) {
                uiState.error = GooglePlayErrorTranslator.friendlyMessage(for: error, authMethod: uiState.account.authMethod)
            }
        }

        // The list is final: show it before the icons arrive.
        uiState.isLoading = false

        // 3. Missing icons, whether or not the sync succeeded (the cached list
        //    may lack some) — but not offline.
        // 4. Release status (edit-free `releases.list`), same conditions.
        if !syncFailedOffline {
            await fetchMissingIcons(using: connection)
            await fetchReleaseSummaries(using: connection, trigger: trigger)
        }

        uiState.isSyncing = false

        // Last, so the activation milestone never holds back the list or icons.
        if let syncedAppCount {
            await firstAppsLoaded.recordAppsLoaded(count: syncedAppCount, provider: .googlePlay, on: .googlePlayAppList)
        }
    }

    // MARK: - Add App Manually

    /// Gated by the account's `apps` rules (`canAdd`) and limited to its per-app
    /// scope. The View hides the entry points too; these guards are the source
    /// of truth.
    func addApp(packageName: String) async {
        analytics.track(.buttonTap(.add, on: .addGooglePlayApp))
        let trimmed = packageName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard uiState.canAddApps else {
            uiState.addError = String(localized: "This account doesn't have permission to add apps.")
            return
        }
        guard uiState.account.allowsApp(bundleId: trimmed) else {
            uiState.addError = String(localized: "This app isn't included in the apps shared with this account.")
            return
        }
        guard !uiState.apps.contains(where: { $0.packageName == trimmed }) else {
            uiState.addError = String(localized: "This app is already in the list.")
            return
        }

        guard let credentials = storedCredentials() else {
            uiState.addError = String(localized: "No credentials found.")
            analytics.track(.action(.addGooglePlayApp, on: .addGooglePlayApp, result: .failure))
            return
        }

        uiState.isAdding = true
        uiState.addError = nil
        var added = false

        do {
            try await accessCheckerFactory(credentials).verifyAccess(packageName: trimmed)

            let item = GooglePlayAppItem(
                id: trimmed,
                packageName: trimmed,
                title: nil,
                isManuallyAdded: true
            )
            uiState.apps = Self.sorted(uiState.apps + [item])
            await saveToStorage()

            uiState.showAddApp = false
            uiState.toastMessage = ToastMessage(String(localized: "App added"), icon: "checkmark.circle.fill")
            Log.print.info("[GooglePlayAppList] Manually added: \(trimmed)")
            added = true
            analytics.track(.action(.addGooglePlayApp, on: .addGooglePlayApp, result: .success))
        } catch {
            analytics.track(.action(.addGooglePlayApp, on: .addGooglePlayApp, result: .failure))
            uiState.addError = GooglePlayErrorTranslator.friendlyMessage(for: error, authMethod: uiState.account.authMethod)
            Log.print.error("[GooglePlayAppList] Add failed: \(error.localizedDescription)")
        }

        uiState.isAdding = false

        // Best effort, once the sheet is closed: the new app's store icon.
        if added {
            await fetchMissingIcons(only: [trimmed], using: connectionFactory(credentials))
        }
    }

    // MARK: - Remove

    /// Gated by the account's `apps` rules (`canDelete`).
    func removeApp(_ app: GooglePlayAppItem) async {
        analytics.track(.buttonTap(.remove, on: .googlePlayAppList))
        guard uiState.canDeleteApps else {
            uiState.toastMessage = ToastMessage(
                String(localized: "This account doesn't have permission to remove apps."),
                icon: "exclamationmark.triangle.fill"
            )
            return
        }
        uiState.apps.removeAll { $0.id == app.id }
        let saved = await saveToStorage()
        analytics.track(.action(.removeGooglePlayApp, on: .googlePlayAppList, result: saved ? .success : .failure))
    }

    // MARK: - Merge

    /// Shared with the background sync leg (`GooglePlayAppListSync.merge`).
    static func merge(
        remote: [StackProtocols.AppInfo],
        into current: [GooglePlayAppItem]
    ) -> [GooglePlayAppItem] {
        GooglePlayAppListSync.merge(remote: remote, into: current)
    }

    // MARK: - Icons

    /// Fills in missing icons from the apps' public Play store pages (core
    /// `AppIcons`, plan D18): no credentials and no edit, so — unlike the
    /// edit-based reads (D14) — safe to run automatically.
    ///
    /// Only apps with no icon yet, inside the account's scope and not already
    /// being looked up (optionally narrowed to `packageNames`), with at most
    /// `maxConcurrentIconFetches` requests in flight. Each icon is applied by
    /// package name onto the *current* list as it arrives, so an app added or
    /// removed meanwhile is never clobbered, and the list is persisted once at
    /// the end when anything changed. `nil` (app not public, lookup failed)
    /// keeps the placeholder; that app is asked again on the next load.
    /// Cancellation (the screen went away) stops scheduling new lookups.
    private func fetchMissingIcons(
        only packageNames: Set<String>? = nil,
        using fetcher: any GooglePlayAppIconFetching
    ) async {
        guard connectivity.isCurrentlyOnline() else { return }

        let candidates = uiState.apps
            .filter { app in
                app.iconUrl == nil
                    && isInScope(app)
                    && !iconFetchesInFlight.contains(app.packageName)
                    && (packageNames?.contains(app.packageName) ?? true)
            }
            .map(\.packageName)
        guard !candidates.isEmpty else { return }

        iconFetchesInFlight.formUnion(candidates)
        var pending = candidates[...]
        var appliedCount = 0

        await withTaskGroup(of: (packageName: String, iconUrl: String?).self) { group in
            for _ in 0..<Self.maxConcurrentIconFetches {
                guard let packageName = pending.popFirst() else { break }
                group.addTask { (packageName, await fetcher.fetchIconUrl(packageName: packageName)) }
            }

            for await result in group {
                iconFetchesInFlight.remove(result.packageName)
                if let iconUrl = result.iconUrl, applyIcon(iconUrl, toPackage: result.packageName) {
                    appliedCount += 1
                }
                if !Task.isCancelled, let packageName = pending.popFirst() {
                    group.addTask { (packageName, await fetcher.fetchIconUrl(packageName: packageName)) }
                }
            }
        }

        // Lookups never started (cancelled) are free to run on the next pass.
        iconFetchesInFlight.subtract(pending)

        guard appliedCount > 0 else { return }
        await saveToStorage()
        Log.print.info("[GooglePlayAppList] Fetched \(appliedCount) of \(candidates.count) missing icons for account: \(self.uiState.account.name)")
    }

    // MARK: - Release status

    /// Shows the cached release status of every listed app (offline-first),
    /// and whether a quota cooldown pauses its refresh.
    private func loadCachedReleaseStatus() async {
        guard uiState.canViewReleases else {
            uiState.releaseStatus = [:]
            uiState.releaseStatusPausedUntil = nil
            return
        }
        var status: [String: [GooglePlayTrackStatusLine]] = [:]
        for app in uiState.apps where isInScope(app) {
            if let cache = await summariesCache(for: app.packageName).load() {
                status[app.packageName] = GooglePlayTrackStatusLine.lines(from: cache)
            }
        }
        uiState.releaseStatus = status
        let cooldown = await summariesRefresher(using: nil).loadCooldown()
        uiState.releaseStatusPausedUntil = cooldown.flatMap { $0.isActive(at: now()) ? $0.until : nil }
    }

    /// Fetches the release summaries of the apps in scope (plan R1, T3)
    /// through `GooglePlayReleaseSummariesRefresher`, which keeps the run under
    /// Google's quota: a load asks nothing during a quota cooldown, skips apps
    /// refreshed in the last minutes and asks only the tracks known to hold a
    /// release; a pull to refresh asks every track of every app; the first
    /// quota hit stops the run and (re)starts the cooldown.
    ///
    /// `releases.list` opens no Play edit, so — unlike the edit-based reads
    /// (D14) — it is safe to run automatically. Never offline, only with the
    /// account's `version` view rule, only for apps in its scope. An app's
    /// cache entry is replaced only when every track asked answered; a failure
    /// keeps its cached status. The refresher saves the entries (the run may
    /// be the Home sync's, shared), then the status lines are read back from
    /// the cache, so apps another run just refreshed show their fresh status.
    private func fetchReleaseSummaries(
        using fetcher: any GooglePlayReleaseSummariesFetching,
        trigger: GooglePlayReleaseSummariesRefresher.Trigger
    ) async {
        guard uiState.canViewReleases, connectivity.isCurrentlyOnline() else { return }

        let packages = uiState.apps
            .filter { isInScope($0) && !summaryFetchesInFlight.contains($0.packageName) }
            .map(\.packageName)
        guard !packages.isEmpty else { return }
        summaryFetchesInFlight.formUnion(packages)
        defer { summaryFetchesInFlight.subtract(packages) }

        let outcome = await summariesRefresher(using: fetcher).refresh(packages: packages, trigger: trigger)

        // Only apps still listed (one may have been removed meanwhile).
        await loadCachedReleaseStatus()
        uiState.releaseStatusPausedUntil = outcome.cooldown.flatMap { $0.isActive(at: now()) ? $0.until : nil }
        Log.print.info("[GooglePlayAppList] Updated release status of \(outcome.entries.count, privacy: .public) of \(packages.count, privacy: .public) apps for account: \(self.uiState.account.name)")
    }

    /// The refresher of this account. Without a `fetcher` it only reads the
    /// cooldown (its `refresh` needs one).
    private func summariesRefresher(using fetcher: (any GooglePlayReleaseSummariesFetching)?) -> GooglePlayReleaseSummariesRefresher {
        GooglePlayReleaseSummariesRefresher(
            accountId: uiState.account.id,
            storage: storage,
            fetcher: fetcher ?? NoReleaseSummariesFetcher(),
            maxConcurrent: Self.maxConcurrentSummaryFetches,
            logTag: "GooglePlayAppList",
            now: now
        )
    }

    private func summariesCache(for packageName: String) -> GooglePlayAppCacheStore<GooglePlayReleaseSummariesCache> {
        GooglePlayAppCacheStore(storage: storage, accountId: uiState.account.id, packageName: packageName)
    }

    /// Sets the icon of the app with `packageName` if it is still listed and
    /// still has none. Returns whether the list changed.
    private func applyIcon(_ iconUrl: String, toPackage packageName: String) -> Bool {
        guard let index = uiState.apps.firstIndex(where: { $0.packageName == packageName }),
              uiState.apps[index].iconUrl == nil else {
            return false
        }
        uiState.apps[index].iconUrl = iconUrl
        return true
    }

    // MARK: - Private

    private var storageKey: String {
        GooglePlayAppItem.cacheKey(accountId: uiState.account.id)
    }

    private static func sorted(_ apps: [GooglePlayAppItem]) -> [GooglePlayAppItem] {
        GooglePlayAppListSync.sorted(apps)
    }

    private func isInScope(_ app: GooglePlayAppItem) -> Bool {
        uiState.account.allowsApp(bundleId: app.packageName)
    }

    private func storedCredentials() -> GooglePlayCredentials? {
        keychain.object(forKey: "credentials.\(uiState.account.id)")
    }

    private func loadFromStorage() async -> [GooglePlayAppItem]? {
        do {
            return try await storage.fetch([GooglePlayAppItem].self, id: storageKey)
        } catch {
            Log.print.error("[GooglePlayAppList] Storage load failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Persists the whole list (API + manual apps) so the next launch can render
    /// it offline. `isManuallyAdded` keeps manual apps distinguishable on merge.
    /// Returns whether the save succeeded (tracked as the remove outcome).
    @discardableResult
    private func saveToStorage() async -> Bool {
        do {
            try await storage.save(uiState.apps, id: storageKey)
            return true
        } catch {
            Log.print.error("[GooglePlayAppList] Storage save failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// Stands in for a connection when the refresher only reads its cooldown.
private struct NoReleaseSummariesFetcher: GooglePlayReleaseSummariesFetching {
    func fetchReleaseSummaries(packageName: String, track: String) async throws -> [GooglePlayReleaseSummaryModel] { [] }
}
