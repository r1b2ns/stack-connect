import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

// T-W05 — Apps list model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that provides offline-first loading,
// live sync, search filtering, favorite toggling, and archive-with-confirmation
// for the Apps List screen.
//
// Mirrors the iOS `AppListViewModel` pattern but adapted to SwiftCrossUI's
// `ObservableObject`/`@Published` and the Windows persistence + connection
// backends. Favorites appear in a separate grouping above All Apps; favorited
// apps do NOT appear in the All Apps grouping (matching the iOS convention).

/// Apps list model for a single account. Owns the state the
/// `WindowsAppsListView` binds to and exposes intents for loading, searching,
/// favoriting, and archiving.
@MainActor
public final class WindowsAppsListModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    /// All non-archived apps for the account (unfiltered source of truth).
    @SwiftCrossUI.Published public private(set) var apps: [AppModel] = []

    /// True while the initial cache load or live sync is in progress.
    @SwiftCrossUI.Published public private(set) var isLoading: Bool = false

    /// Non-nil when a live sync fails; the cached data remains visible.
    @SwiftCrossUI.Published public private(set) var syncError: String? = nil

    /// The current search query. Setting this re-computes the filtered
    /// groupings (`favoriteApps` and `allApps`).
    @SwiftCrossUI.Published public var searchQuery: String = ""

    /// When non-nil, the confirmation UI is shown for archiving this app id.
    @SwiftCrossUI.Published public var archiveConfirmingId: String? = nil

    // MARK: - Configuration

    /// The account this list displays apps for.
    public let accountId: String

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let connection: AppleConnectionProtocol?

    // MARK: - Init

    /// Creates a new apps list model.
    ///
    /// - Parameters:
    ///   - accountId: The account whose apps to display.
    ///   - storage: Persistent storage backend (SQLite on Windows).
    ///   - connection: Optional Apple connection for live sync. When nil,
    ///     only cached data is shown (useful for offline or test scenarios).
    public init(
        accountId: String,
        storage: PersistentStorable,
        connection: AppleConnectionProtocol? = nil
    ) {
        self.accountId = accountId
        self.storage = storage
        self.connection = connection
    }

    // MARK: - Computed Groupings

    /// Favorite apps, filtered by the current search query.
    /// Favorites appear in their own section above All Apps.
    public var favoriteApps: [AppModel] {
        applySearch(to: apps.filter { $0.isFavorite && !$0.isArchived })
    }

    /// Non-favorite, non-archived apps, filtered by the current search query.
    /// Favorited apps are excluded from this list (no duplication).
    public var allApps: [AppModel] {
        applySearch(to: apps.filter { !$0.isFavorite && !$0.isArchived })
    }

    /// True when no apps exist at all (empty cache and no sync result).
    public var isEmpty: Bool {
        apps.filter { !$0.isArchived }.isEmpty
    }

    /// True when the search produces no results in either grouping.
    public var isSearchEmpty: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
            && favoriteApps.isEmpty
            && allApps.isEmpty
    }

    // MARK: - Load (Offline-First + Live Sync)

    /// Loads apps from cache first, then syncs from the live API.
    ///
    /// 1. Fetch all `AppModel` from storage filtered by `accountId`.
    /// 2. Display cached apps immediately (`isLoading` goes false after cache).
    /// 3. If a connection is available, sync from the API:
    ///    - `isLoading` goes true during sync.
    ///    - On success, merge remote apps with cached local flags
    ///      (isFavorite, isArchived), update the UI, and persist.
    ///    - On failure, set `syncError`; cached data remains visible.
    public func loadApps() async {
        isLoading = true
        syncError = nil

        // Phase 1: Load from cache
        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let cached = allApps
                .filter { $0.accountId == accountId }
                .sorted(by: Self.appSortOrder)
            apps = cached
        } catch {
            // Cache load failure: no data to show, but not a sync error.
            apps = []
        }

        // If no connection, we are done after cache.
        guard let connection else {
            isLoading = false
            return
        }

        // Phase 2: Live sync — keep isLoading true for the sync indicator.
        // If we had cached data, the user already sees it; the loading
        // indicator signals that a background refresh is in progress.
        do {
            let remoteAppInfos = try await connection.fetchApps()

            // Merge remote data with local flags (isFavorite, isArchived)
            let cachedById = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            let merged = remoteAppInfos.map { info -> AppModel in
                let cached = cachedById[info.id]
                return AppModel(
                    id: info.id,
                    name: info.name,
                    bundleId: info.bundleId,
                    platform: info.platform,
                    accountId: accountId,
                    iconUrl: cached?.iconUrl,
                    appStoreState: cached?.appStoreState,
                    versionString: cached?.versionString,
                    lastModifiedDate: cached?.lastModifiedDate,
                    isArchived: cached?.isArchived ?? false,
                    isFavorite: cached?.isFavorite ?? false,
                    hasReviewPending: cached?.hasReviewPending ?? false,
                    platformVersions: cached?.platformVersions
                )
            }.sorted(by: Self.appSortOrder)

            apps = merged

            // Persist merged models
            for app in merged {
                try await storage.save(app, id: "\(accountId).\(app.id)")
            }
        } catch {
            syncError = "Sync failed. Showing cached data."
        }

        isLoading = false
    }

    // MARK: - Search

    /// Pure helper: returns true when the app's name or bundleId contains the
    /// query as a case-insensitive substring. Exposed as a static so it can be
    /// unit-tested independently (TC-078).
    public static func appMatchesSearch(_ app: AppModel, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let lowered = trimmed.lowercased()
        return app.name.lowercased().contains(lowered)
            || app.bundleId.lowercased().contains(lowered)
    }

    // MARK: - Favorite Toggle

    /// Toggles the `isFavorite` flag for the given app. The change is applied
    /// optimistically to the UI, then persisted. On persistence failure the
    /// change is reverted and `syncError` is set.
    public func toggleFavorite(appId: String) async {
        guard let idx = apps.firstIndex(where: { $0.id == appId }) else { return }

        // Optimistic update
        apps[idx].isFavorite.toggle()
        let updated = apps[idx]

        do {
            try await storage.save(updated, id: "\(accountId).\(updated.id)")
        } catch {
            // Revert on failure
            apps[idx].isFavorite.toggle()
            syncError = "Failed to update favorite."
        }
    }

    // MARK: - Archive Flow (Intent + Confirmation)

    /// Surfaces the archive-confirmation intent for the given app.
    /// The View/coordinator owns the confirmation UI; this model just
    /// exposes the id that needs confirmation.
    public func archiveApp(appId: String) {
        syncError = nil
        archiveConfirmingId = appId
    }

    /// Cancels a pending archive confirmation without changing the app.
    public func cancelArchive() {
        archiveConfirmingId = nil
    }

    /// Executes the archive after confirmation. Removes the app from the
    /// main list (sets `isArchived = true`), persists the change, and clears
    /// the confirmation state.
    ///
    /// On persistence failure the optimistic change is **reverted** and
    /// `syncError` is set (revert-on-failure discipline).
    public func archiveAppConfirmed(appId: String) async {
        guard let idx = apps.firstIndex(where: { $0.id == appId }) else {
            archiveConfirmingId = nil
            return
        }

        // Optimistic update
        apps[idx].isArchived = true
        let updated = apps[idx]
        archiveConfirmingId = nil

        do {
            try await storage.save(updated, id: "\(accountId).\(updated.id)")
        } catch {
            // Revert on failure
            apps[idx].isArchived = false
            syncError = "Failed to archive app."
        }
    }

    // MARK: - Private Helpers

    /// Applies the current search query to a pre-filtered list of apps.
    private func applySearch(to source: [AppModel]) -> [AppModel] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return source }
        return source.filter { Self.appMatchesSearch($0, query: trimmed) }
    }

    /// Sort order: most-recently modified first; apps without a date sort
    /// alphabetically by name at the end. Matches the iOS convention.
    private static func appSortOrder(_ a: AppModel, _ b: AppModel) -> Bool {
        switch (a.lastModifiedDate, b.lastModifiedDate) {
        case let (dateA?, dateB?): return dateA > dateB
        case (_?, nil):            return true
        case (nil, _?):            return false
        case (nil, nil):           return a.name < b.name
        }
    }
}
