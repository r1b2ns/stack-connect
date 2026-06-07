import Foundation
import StackHomeCore
import WidgetKit
#if canImport(Combine)
import Combine
#endif
#if DEBUG
import UIKit
import UserNotifications
#endif

// The sync pipeline itself now lives in StackHomeCore (Foundation-pure,
// `StackHomeCore.SyncService<Credentials>`, T-A9). This file keeps only the
// iOS-side concerns:
//
//  1. `SyncService` — a thin `ObservableObject` adapter that owns a core
//     `SyncService<AppleCredentials>`, subscribes to its `onStateChanged`
//     callback, and republishes `state` via `@Published` so the existing
//     `HomeViewModel`/`AllReviewsViewModel` Combine bindings (`$state`) and the
//     SwiftUI banner keep working unchanged. As of T-A10 the adapter also
//     conforms to `HomeSyncObserving` so the now-core `HomeViewModel` consumes
//     it as its sync dependency.
//  2. `AppleSyncSideEffects` — the concrete `SyncSideEffects` conformance that
//     performs the Apple-only effects the core deliberately abstracts away:
//     WidgetKit timeline reloads, widget icon preloading, and the "fake push"
//     local notifications (incl. the DEBUG background "sync started" banner).

// MARK: - iOS adapter

@MainActor
final class SyncService: ObservableObject {

    typealias AppleConnectionFactory = @Sendable (AppleCredentials) -> any AppleAccountSyncing

    static let shared = SyncService()

    /// Republished snapshot of the core pipeline's `SyncState`, kept in sync via
    /// the core service's `onStateChanged` callback. `@Published` preserves the
    /// `$state` Combine publisher the Home/AllReviews view models bind to.
    @Published private(set) var state = SyncState()

    private let core: StackHomeCore.SyncService<AppleCredentials>

    /// Extra observer registered by the core `HomeViewModel` via
    /// `HomeSyncObserving.observeSyncState`. The adapter already owns the core
    /// service's single `onStateChanged` slot to drive `@Published state`, so it
    /// multiplexes that one callback out to this observer too.
    private var homeStateObserver: ((SyncState) -> Void)?

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        appleConnectionFactory: AppleConnectionFactory? = nil
    ) {
        let resolvedStorage: any PersistentStorable = storage ?? SwiftDataStorable.shared
        let factory: StackHomeCore.SyncService<AppleCredentials>.AppleConnectionFactory =
            appleConnectionFactory ?? { AppleAccountConnection(credentials: $0) }
        core = StackHomeCore.SyncService(
            storage: resolvedStorage,
            keychain: keychain,
            appleConnectionFactory: factory,
            sideEffects: AppleSyncSideEffects(storage: resolvedStorage)
        )
        // Mirror the initial snapshot, then republish every transition.
        state = core.state
        core.onStateChanged = { [weak self] newState in
            guard let self else { return }
            self.state = newState
            self.homeStateObserver?(newState)
        }
    }

    /// Fire-and-forget. Safe to call repeatedly — already-running syncs are
    /// coalesced by the core service.
    @discardableResult
    func syncAll(mode: SyncMode = .full) -> Task<Void, Never> {
        core.syncAll(mode: mode)
    }
}

// MARK: - HomeSyncObserving

/// Lets the migrated core `HomeViewModel` consume this adapter as its sync
/// dependency. It observes through the adapter (which already republishes via
/// `@Published`) rather than touching the core service's `onStateChanged` slot
/// directly, so the two consumers don't contend for it.
extension SyncService: HomeSyncObserving {
    var syncState: SyncState { state }

    @discardableResult
    func triggerSync() -> Task<Void, Never> {
        syncAll()
    }

    func observeSyncState(_ onChange: @escaping (SyncState) -> Void) {
        homeStateObserver = onChange
    }
}

// MARK: - Apple side effects

/// iOS implementation of the core's `SyncSideEffects` seam. Performs the
/// WidgetKit / UserNotifications work the Foundation-pure core cannot.
struct AppleSyncSideEffects: SyncSideEffects {

    private let storage: PersistentStorable

    init(storage: PersistentStorable) {
        self.storage = storage
    }

    func syncDidStart(mode: SyncMode, accountCount: Int) async {
        #if DEBUG
        await Self.postDebugSyncStartedNotification(mode: mode, accountCount: accountCount)
        #endif
    }

    func syncDidFinish(mode: SyncMode, changes: SyncChange) async {
        await preloadWidgetIcons()
        WidgetCenter.shared.reloadAllTimelines()

        // "Fake push": surface status changes and new reviews as local
        // notifications, but only for background (lightweight) syncs — in the
        // foreground the user already sees these updates on screen.
        if mode == .lightweight {
            await LocalNotificationService.scheduleStatusChanges(changes.statusChanges)
            await LocalNotificationService.scheduleNewReviews(changes.newReviews)
        }
    }

    /// Caches app icons into the shared App Group container so the widget can
    /// render real icons instead of placeholders.
    private func preloadWidgetIcons() async {
        guard let apps: [AppModel] = try? await storage.fetchAll(AppModel.self) else { return }
        let iconURLs = apps.compactMap { $0.iconUrl }
        await WidgetIconCache.preload(iconURLs: iconURLs)
    }

    #if DEBUG
    private static func postDebugSyncStartedNotification(mode: SyncMode, accountCount: Int) async {
        // Only surface the "sync started" notification when the app is in the
        // background — a banner while the user is actively using the app is noise.
        let appState = await MainActor.run { UIApplication.shared.applicationState }
        guard appState == .background else { return }

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
}
