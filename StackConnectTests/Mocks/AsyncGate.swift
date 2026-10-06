import Foundation

/// A gate a mock handler can wait on, so a test can hold a call mid-flight
/// (e.g. to start a second load while the first is still running) and then let
/// it finish with `open()`. Once open it stays open.
actor AsyncGate {

    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0

    /// Suspends until `open()` (returns at once when already open).
    func wait() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    /// Yields until `count` callers reached `wait()` (bounded, so a broken test
    /// fails instead of hanging).
    func waitForArrivals(_ count: Int = 1) async {
        for _ in 0..<10_000 where arrivals < count {
            await Task.yield()
        }
    }
}
