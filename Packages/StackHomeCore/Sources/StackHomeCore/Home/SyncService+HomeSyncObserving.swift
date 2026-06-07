import Foundation

/// Adapts the core sync pipeline to the `HomeSyncObserving` slice the
/// `HomeViewModel` consumes.
///
/// This makes `SyncService<Credentials>` directly usable as the view model's
/// sync dependency on the Windows port and in `StackHomeCoreTests`. On iOS the
/// app instead supplies its `ObservableObject` `SyncService` adapter (which
/// republishes via `@Published`); both satisfy the same protocol.
///
/// `observeSyncState` routes through `onStateChanged`. The pipeline exposes a
/// single `onStateChanged` slot, so when the iOS app already owns that callback
/// it uses the adapter conformance instead of this one — avoiding two observers
/// contending for the slot.
extension SyncService: HomeSyncObserving {
    public var syncState: SyncState { state }

    @discardableResult
    public func triggerSync() -> Task<Void, Never> {
        syncAll()
    }

    public func observeSyncState(_ onChange: @escaping (SyncState) -> Void) {
        onStateChanged = onChange
    }
}
