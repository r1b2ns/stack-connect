import Foundation
import Network
import os

// MARK: - Provider abstraction

/// A synchronous, actor-agnostic "are we online right now?" probe.
///
/// Kept deliberately tiny (ISP) so non-`MainActor` callers — e.g.
/// `AppleAccountConnection`, which is `@unchecked Sendable` and runs its guard
/// off the main actor — can check connectivity without hopping actors, and so
/// tests can inject a deterministic value.
protocol ConnectivityProviding: Sendable {
    func isCurrentlyOnline() -> Bool
}

// MARK: - Connectivity Monitor

/// Observes network reachability via `NWPathMonitor` and exposes it two ways:
///
/// - `isConnected` (`@Published`, MainActor) drives the global offline banner.
/// - `isCurrentlyOnline()` (`nonisolated`) is a lock-backed synchronous snapshot
///   for the write-guard in `AppleAccountConnection`, which runs off the main
///   actor and cannot `await`.
///
/// Mirrors the singleton shape of `SyncService`. `init`/`shared` are
/// `nonisolated` so the shared instance can be used as a default argument from
/// the ~50 non-isolated `AppleAccountConnection(credentials:)` call sites.
@MainActor
final class ConnectivityMonitor: ObservableObject, ConnectivityProviding {

    nonisolated static let shared = ConnectivityMonitor()

    /// Observable connectivity for SwiftUI. Starts optimistically `true` so the
    /// banner never flashes before the first path update lands.
    @Published private(set) var isConnected: Bool = true

    /// Thread-safe synchronous snapshot, readable from any isolation domain.
    /// Backs `isCurrentlyOnline()` so the write-guard never blocks on a hop to
    /// the main actor.
    private nonisolated let onlineFlag = OSAllocatedUnfairLock<Bool>(initialState: true)

    /// `nonisolated` (both types are `Sendable`) so the `nonisolated init` can
    /// configure and start the monitor without imposing main-actor isolation on
    /// the singleton.
    private nonisolated let monitor = NWPathMonitor()
    private nonisolated let queue = DispatchQueue(label: "com.stackconnect.connectivity", qos: .utility)

    nonisolated init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            // (a) Update the lock-backed synchronous flag first, so a guard on
            //     another thread observes the freshest value immediately.
            self?.onlineFlag.withLock { $0 = isOnline }
            // (b) Publish to SwiftUI on the MainActor.
            Task { @MainActor [weak self] in
                self?.applyConnected(isOnline)
            }
        }
        monitor.start(queue: queue)
    }

    // MARK: - ConnectivityProviding

    nonisolated func isCurrentlyOnline() -> Bool {
        onlineFlag.withLock { $0 }
    }

    // MARK: - Private (MainActor)

    private func applyConnected(_ value: Bool) {
        guard isConnected != value else { return }
        isConnected = value
        Log.print.info("[Connectivity] \(value ? "online" : "offline")")
    }
}
