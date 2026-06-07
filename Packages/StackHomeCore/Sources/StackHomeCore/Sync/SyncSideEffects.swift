import Foundation

/// Injectable seam for the Apple-only side effects the sync pipeline triggers.
///
/// The core `SyncService` is Foundation-pure: it must not `import WidgetKit`,
/// `UIKit` or `UserNotifications`. Those effects (reloading widget timelines,
/// preloading widget icons into the App Group, and the "fake push" local
/// notifications) are abstracted here so the pipeline can call them without
/// knowing the platform.
///
/// - On iOS, `AppleSyncSideEffects` (app target) performs the real WidgetKit /
///   UserNotifications work.
/// - The default `NoopSyncSideEffects` (and any Windows implementation) does
///   nothing, so core compiles and runs SDK-free on the Windows toolchain.
///
/// All methods are `async` because the iOS implementation does asynchronous
/// work (icon preloading, notification authorization/scheduling). `Sendable`
/// because the pipeline hops actors.
public protocol SyncSideEffects: Sendable {

    /// Called when a sync run begins, after the eligible Apple accounts are
    /// resolved. iOS uses this for the DEBUG-only background "sync started"
    /// notification; the count is the number of accounts about to sync.
    func syncDidStart(mode: SyncMode, accountCount: Int) async

    /// Called once a sync run has persisted everything, before the final state
    /// transition is published. iOS reloads widget timelines and preloads icons.
    func syncDidFinish(mode: SyncMode, changes: SyncChange) async
}

public extension SyncSideEffects {
    func syncDidStart(mode: SyncMode, accountCount: Int) async {}
    func syncDidFinish(mode: SyncMode, changes: SyncChange) async {}
}

/// Default no-op side effects — used by the Windows app and by core unit tests.
public struct NoopSyncSideEffects: SyncSideEffects {
    public init() {}
}
