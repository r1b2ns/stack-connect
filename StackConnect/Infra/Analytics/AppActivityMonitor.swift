import StackProtocols
import UIKit

/// Tells `AnalyticsService` whether the app is active, and when it becomes
/// active. A seam so the `screen_view` hold-back is unit tested without UIKit.
@MainActor
protocol AppActivityMonitoring: AnyObject {
    /// `true` while the app is in the foreground and active.
    var isActive: Bool { get }

    /// Registers `handler`, called every time the app becomes active (after
    /// the system's own `didBecomeActive` observers ran). Called once.
    func observeDidBecomeActive(_ handler: @escaping @MainActor @Sendable () -> Void)
}

/// `UIApplication`-backed `AppActivityMonitoring`.
///
/// The handler runs one main-queue turn *after* `didBecomeActiveNotification`:
/// every observer of a notification is called synchronously in the same post,
/// in an unspecified order, and Firebase Analytics starts its session from its
/// own `didBecomeActive` observer. Hopping once guarantees our held
/// `screen_view` events are logged after the session started.
@MainActor
final class UIApplicationActivityMonitor: AppActivityMonitoring {

    private let center: NotificationCenter
    private var observer: NSObjectProtocol?

    /// Never removed: the monitor lives as long as `AnalyticsService.shared`.
    init(center: NotificationCenter = .default) {
        self.center = center
    }

    /// Read on every call (not cached), so it is correct even when the
    /// monitor was built before the first scene connected.
    var isActive: Bool {
        UIApplication.shared.applicationState == .active
    }

    func observeDidBecomeActive(_ handler: @escaping @MainActor @Sendable () -> Void) {
        guard observer == nil else { return }
        observer = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler() }
            }
        }
    }
}

/// `screen_view` events tracked while the app was not active yet, in order.
///
/// A view's `onAppear` can run during scene connection, before the app is
/// active and before Firebase started the session; Firebase then records that
/// manual `screen_view` without its screen parameters ("(not set)" in GA4).
/// `AnalyticsService` holds such events here and sends them once the app is
/// active. Consecutive identical events are kept once (a root view appearing
/// twice while launching is still one screen view).
struct PendingScreenViewQueue: Equatable, Sendable {

    private(set) var events: [AnalyticsEvent] = []

    var isEmpty: Bool { events.isEmpty }

    mutating func enqueue(_ event: AnalyticsEvent) {
        guard events.last != event else { return }
        events.append(event)
    }

    /// Returns every held event, in order, and empties the queue.
    mutating func drain() -> [AnalyticsEvent] {
        defer { events.removeAll() }
        return events
    }

    mutating func removeAll() {
        events.removeAll()
    }
}
