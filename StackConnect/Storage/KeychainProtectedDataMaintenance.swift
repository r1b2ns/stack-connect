import Foundation
import UIKit

/// Keeps the real Keychain healthy across lock states: whenever protected data
/// is available (at launch if it already is, then on every
/// `protectedDataDidBecomeAvailable` and `didBecomeActive`) it runs the
/// one-time `KeychainAccessibilityMigration` (a no-op once recorded) and then
/// replays the writes `KeychainStorable` deferred while the device was locked.
///
/// Started from `AppDelegate` outside the fake data mode and unit-test hosts:
/// `start(with:)` only accepts the real `KeychainStorable`.
@MainActor
final class KeychainProtectedDataMaintenance {

    static let shared = KeychainProtectedDataMaintenance()

    private let notificationCenter: NotificationCenter
    private let isProtectedDataAvailable: @MainActor () -> Bool
    private var keychain: KeychainStorable?
    private var migration: KeychainAccessibilityMigration?
    private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = .default,
        isProtectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
    ) {
        self.notificationCenter = notificationCenter
        self.isProtectedDataAvailable = isProtectedDataAvailable
    }

    /// Starts on `keyStore` when it is the real Keychain (not the fake data
    /// mode's in-memory store). Starting twice does nothing.
    func start(with keyStore: KeyStorable, defaults: UserDefaults = .standard) {
        guard observers.isEmpty else { return }
        guard let keychain = keyStore as? KeychainStorable else {
            Log.print.info("[Keychain] Maintenance skipped: not the real Keychain")
            return
        }
        self.keychain = keychain
        self.migration = KeychainAccessibilityMigration(keychain: keychain, defaults: defaults)

        for name in [UIApplication.protectedDataDidBecomeAvailableNotification,
                     UIApplication.didBecomeActiveNotification] {
            // UIKit posts these on the main thread: run right away there.
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.runMaintenance() }
                } else {
                    Task { @MainActor in self?.runMaintenance() }
                }
            })
        }

        if isProtectedDataAvailable() {
            runMaintenance()
        } else {
            Log.print.notice("[Keychain] Protected data unavailable at launch: maintenance waits for unlock")
        }
    }

    /// Migrates (once) then flushes the deferred writes.
    func runMaintenance() {
        guard let keychain else { return }
        migration?.runIfNeeded()
        keychain.flushPendingWrites()
    }

    /// Stops observing (tests; the shared instance lives as long as the app).
    func stop() {
        observers.forEach(notificationCenter.removeObserver)
        observers = []
        keychain = nil
        migration = nil
    }
}
