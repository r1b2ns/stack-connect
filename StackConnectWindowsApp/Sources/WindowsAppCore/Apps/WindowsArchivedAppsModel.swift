import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

// T-W07 — Archived apps model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that provides offline-first loading
// and restore-with-confirmation for the Archived Apps screen. Mirrors
// `WindowsAppsListModel` conventions (same package, `@MainActor`,
// `SwiftCrossUI.ObservableObject`/`@SwiftCrossUI.Published`, DI of `storage`
// + optional `connection`, offline-first cache load, revert-on-failure).
//
// Archived state is local-only (the API has no concept of archived apps), so
// `loadArchivedApps()` loads from persistent storage and filters by
// `isArchived == true && accountId`. There is no live sync phase.
//
// Restore flow mirrors the archive flow in `WindowsAppsListModel`:
// `restoreApp(appId:)` sets `restoreConfirmingId` (the confirmation intent),
// `cancelRestore()` clears it, and `restoreAppConfirmed(appId:)` optimistically
// sets `isArchived = false`, removes the app from `archivedApps`, persists the
// change, and reverts on persistence failure.

/// Archived apps model for a single account. Owns the state the
/// `WindowsArchivedAppsView` binds to and exposes intents for loading and
/// restoring archived apps.
@MainActor
public final class WindowsArchivedAppsModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    /// All archived apps for the account (only `isArchived == true`).
    @SwiftCrossUI.Published public private(set) var archivedApps: [AppModel] = []

    /// True while the cache load is in progress.
    @SwiftCrossUI.Published public private(set) var isLoading: Bool = false

    /// Non-nil when a persistence operation fails; the cached data remains visible.
    @SwiftCrossUI.Published public private(set) var syncError: String? = nil

    /// When non-nil, the confirmation UI is shown for restoring this app id.
    @SwiftCrossUI.Published public var restoreConfirmingId: String? = nil

    // MARK: - Configuration

    /// The account this list displays archived apps for.
    public let accountId: String

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let connection: AppleConnectionProtocol?

    // MARK: - Init

    /// Creates a new archived apps model.
    ///
    /// - Parameters:
    ///   - accountId: The account whose archived apps to display.
    ///   - storage: Persistent storage backend (SQLite on Windows).
    ///   - connection: Optional Apple connection. Currently unused (archived
    ///     state is local-only), but accepted for symmetry with
    ///     `WindowsAppsListModel` and future extensibility.
    public init(
        accountId: String,
        storage: PersistentStorable,
        connection: AppleConnectionProtocol? = nil
    ) {
        self.accountId = accountId
        self.storage = storage
        self.connection = connection
    }

    // MARK: - Computed Properties

    /// True when no archived apps exist (empty cache after load).
    public var isEmpty: Bool {
        archivedApps.isEmpty
    }

    // MARK: - Load (Offline-First Cache)

    /// Loads archived apps from persistent storage, filtering by
    /// `isArchived == true` and `accountId`.
    ///
    /// Archived state is local-only (the API has no concept of archived apps),
    /// so there is no live sync phase. The model simply reads from the cache.
    public func loadArchivedApps() async {
        isLoading = true
        syncError = nil

        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let archived = allApps
                .filter { $0.accountId == accountId && $0.isArchived }
                .sorted(by: Self.appSortOrder)
            archivedApps = archived
        } catch {
            archivedApps = []
        }

        isLoading = false
    }

    // MARK: - Restore Flow (Intent + Confirmation)

    /// Surfaces the restore-confirmation intent for the given app.
    /// The View/coordinator owns the confirmation UI; this model just
    /// exposes the id that needs confirmation.
    public func restoreApp(appId: String) {
        syncError = nil
        restoreConfirmingId = appId
    }

    /// Cancels a pending restore confirmation without changing the app.
    public func cancelRestore() {
        restoreConfirmingId = nil
    }

    /// Executes the restore after confirmation. Sets `isArchived = false` on
    /// the app, removes it from `archivedApps`, persists the change, and
    /// clears the confirmation state.
    ///
    /// On persistence failure the optimistic change is **reverted** and
    /// `syncError` is set (revert-on-failure discipline).
    public func restoreAppConfirmed(appId: String) async {
        guard let idx = archivedApps.firstIndex(where: { $0.id == appId }) else {
            restoreConfirmingId = nil
            return
        }

        // Capture the original app before mutation for revert.
        let originalApp = archivedApps[idx]

        // Optimistic update: set isArchived = false and remove from list.
        var updated = archivedApps[idx]
        updated.isArchived = false
        archivedApps.remove(at: idx)
        restoreConfirmingId = nil

        do {
            try await storage.save(updated, id: "\(accountId).\(updated.id)")
        } catch {
            // Revert on failure: re-insert the original app at the same position
            // (or at the end if the index is now out of bounds).
            let revertIdx = min(idx, archivedApps.count)
            archivedApps.insert(originalApp, at: revertIdx)
            syncError = "Failed to restore app."
        }
    }

    // MARK: - Private Helpers

    /// Sort order: alphabetically by name. Matches the convention used by
    /// `WindowsAppsListModel` for the fallback case (no dates).
    private static func appSortOrder(_ a: AppModel, _ b: AppModel) -> Bool {
        switch (a.lastModifiedDate, b.lastModifiedDate) {
        case let (dateA?, dateB?): return dateA > dateB
        case (_?, nil):            return true
        case (nil, _?):            return false
        case (nil, nil):           return a.name < b.name
        }
    }
}
