import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol GooglePlayAppListViewModelProtocol: ObservableObject {
    var uiState: GooglePlayAppListUiState { get set }
    func load() async
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

    /// Manual "add app by package name" is allowed by the account's rules.
    var canAddApps: Bool {
        account.canAdd(.apps)
    }

    /// Removing a manually added app is allowed by the account's rules.
    var canDeleteApps: Bool {
        account.canDelete(.apps)
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

    @Published var uiState: GooglePlayAppListUiState

    private let keychain: KeyStorable
    private let storage: PersistentStorable
    private let connectionFactory: ConnectionFactory
    private let accessCheckerFactory: AccessCheckerFactory
    private let connectivity: ConnectivityProviding

    /// Package names whose icon is being looked up, so overlapping passes (a pull
    /// to refresh during the first load, a manual add) never ask twice.
    private var iconFetchesInFlight = Set<String>()

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) },
        accessCheckerFactory: @escaping AccessCheckerFactory = {
            GooglePlayCoreAccessChecker(appDetails: GooglePlayAccountConnection(credentials: $0))
        },
        connectivity: ConnectivityProviding = ConnectivityMonitor.shared
    ) {
        self.uiState = GooglePlayAppListUiState(account: account)
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
        self.connectionFactory = connectionFactory
        self.accessCheckerFactory = accessCheckerFactory
        self.connectivity = connectivity
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
        uiState.error = nil

        // 1. Cached list first (offline-first). Defense-in-depth: hide any cached
        //    row outside the scope (the next save drops it from the cache).
        if let cached = await loadFromStorage()?.filter(isInScope), !cached.isEmpty {
            uiState.apps = Self.sorted(cached)
        }
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

        do {
            let remoteApps = try await connection.fetchApps().filter {
                self.uiState.account.allowsApp(bundleId: $0.bundleId)
            }
            uiState.apps = Self.merge(remote: remoteApps, into: uiState.apps)
            await saveToStorage()
            Log.print.info("[GooglePlayAppList] Synced \(remoteApps.count) apps for account: \(self.uiState.account.name)")
        } catch {
            Log.print.error("[GooglePlayAppList] Sync failed: \(error.localizedDescription)")
            syncFailedOffline = GooglePlayErrorTranslator.isOffline(error)
            // Offline with a cached list: the global offline banner already says
            // so — keep the list without a second warning.
            if !(syncFailedOffline && !uiState.apps.isEmpty) {
                uiState.error = GooglePlayErrorTranslator.friendlyMessage(for: error)
            }
        }

        // The list is final: show it before the icons arrive.
        uiState.isLoading = false

        // 3. Missing icons, whether or not the sync succeeded (the cached list
        //    may lack some) — but not offline.
        if !syncFailedOffline {
            await fetchMissingIcons(using: connection)
        }

        uiState.isSyncing = false
    }

    // MARK: - Add App Manually

    /// Gated by the account's `apps` rules (`canAdd`) and limited to its per-app
    /// scope. The View hides the entry points too; these guards are the source
    /// of truth.
    func addApp(packageName: String) async {
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
        } catch {
            uiState.addError = GooglePlayErrorTranslator.friendlyMessage(for: error)
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
        guard uiState.canDeleteApps else {
            uiState.toastMessage = ToastMessage(
                String(localized: "This account doesn't have permission to remove apps."),
                icon: "exclamationmark.triangle.fill"
            )
            return
        }
        uiState.apps.removeAll { $0.id == app.id }
        await saveToStorage()
    }

    // MARK: - Merge

    /// API apps are the source of truth; manually added apps the API doesn't
    /// return are kept. Deduped by package name — when the API starts returning a
    /// manually added app, the API entry (with its display name) wins. The API
    /// has no icons, so each entry keeps the cached icon of the current item with
    /// the same package name.
    static func merge(
        remote: [StackProtocols.AppInfo],
        into current: [GooglePlayAppItem]
    ) -> [GooglePlayAppItem] {
        var seen = Set<String>()
        var merged: [GooglePlayAppItem] = []
        var cachedIcons: [String: String] = [:]
        for app in current {
            if let iconUrl = app.iconUrl, cachedIcons[app.packageName] == nil {
                cachedIcons[app.packageName] = iconUrl
            }
        }

        for app in remote where seen.insert(app.bundleId).inserted {
            merged.append(GooglePlayAppItem(
                id: app.bundleId,
                packageName: app.bundleId,
                title: app.name.isEmpty ? nil : app.name,
                isManuallyAdded: false,
                iconUrl: cachedIcons[app.bundleId]
            ))
        }

        for app in current where app.isManuallyAdded && seen.insert(app.packageName).inserted {
            merged.append(app)
        }

        return sorted(merged)
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
        apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
    private func saveToStorage() async {
        do {
            try await storage.save(uiState.apps, id: storageKey)
        } catch {
            Log.print.error("[GooglePlayAppList] Storage save failed: \(error.localizedDescription)")
        }
    }
}
