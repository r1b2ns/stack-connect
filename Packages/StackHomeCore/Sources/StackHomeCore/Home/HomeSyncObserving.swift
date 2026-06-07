import Foundation

/// The slice of the sync pipeline the core `HomeViewModel` depends on.
///
/// `HomeViewModel` must not be generic over the iOS-only credentials type, so it
/// talks to the sync pipeline through this minimal, Foundation-pure protocol
/// instead of holding a concrete `SyncService<Credentials>`. It exposes:
///
/// - `syncState`: the latest snapshot, mirrored into `HomeUiState.syncState`.
/// - `triggerSync()`: fire-and-forget sync (coalesced by the pipeline —
///   TC-018/TC-078). Returns a `Task` callers may await (used by `refresh()`).
/// - `observeSyncState(_:)`: registers a MainActor callback fired on every
///   `SyncState` transition, so the view model can reload the dashboard when a
///   sync finishes (`lastSyncedAt` advances).
///
/// On iOS the concrete `SyncService<AppleCredentials>` is adapted to this
/// protocol; the Windows port supplies its own conformer over the same core
/// `SyncService`.
@MainActor
public protocol HomeSyncObserving: AnyObject {
    /// Latest sync snapshot.
    var syncState: SyncState { get }

    /// Fire-and-forget sync. Already-running syncs are coalesced by the pipeline.
    @discardableResult
    func triggerSync() -> Task<Void, Never>

    /// Registers a callback fired on the MainActor for every `SyncState`
    /// transition. Implementations may support a single observer (the view
    /// model); a later registration replaces an earlier one.
    func observeSyncState(_ onChange: @escaping (SyncState) -> Void)
}
