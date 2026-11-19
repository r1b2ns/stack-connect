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

    /// Suspends until at least `count` callers reached `wait()`. Bounded by
    /// wall-clock time, not by a number of yields: the callers may first go
    /// through the main actor, storage or other executors, so a yield budget
    /// can run out before they arrive on a busy machine (which made
    /// bounded-concurrency tests flaky). `timeout` only matters when a test is
    /// broken: it then fails on its assertions instead of hanging.
    func waitForArrivals(_ count: Int = 1, timeout: Duration = .seconds(10)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while arrivals < count, clock.now < deadline {
            await Task.yield()
            if arrivals < count {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    /// Lets every other task run for a while without the gate opening, so a
    /// broken concurrency bound would show up as extra arrivals. Call it after
    /// `waitForArrivals(limit)`: with a correct bound nobody else can arrive
    /// while the gate is closed, so the count read afterwards is exact.
    func settle(yields: Int = 1_000, sleep: Duration = .milliseconds(50)) async {
        for _ in 0..<yields {
            await Task.yield()
        }
        try? await Task.sleep(for: sleep)
        for _ in 0..<yields {
            await Task.yield()
        }
    }
}
