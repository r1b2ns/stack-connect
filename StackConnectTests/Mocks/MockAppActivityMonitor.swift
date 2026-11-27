import Foundation
@testable import StackConnect

/// Drives `AnalyticsService`'s "is the app active" source by hand.
@MainActor
final class MockAppActivityMonitor: AppActivityMonitoring {

    var isActive: Bool
    private(set) var observeCount = 0
    private var handler: (@MainActor @Sendable () -> Void)?

    init(isActive: Bool) {
        self.isActive = isActive
    }

    func observeDidBecomeActive(_ handler: @escaping @MainActor @Sendable () -> Void) {
        observeCount += 1
        self.handler = handler
    }

    /// Simulates `didBecomeActive`: flips `isActive` and calls the handler.
    func becomeActive() {
        isActive = true
        handler?()
    }

    func resignActive() {
        isActive = false
    }
}
