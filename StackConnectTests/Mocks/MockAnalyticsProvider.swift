import Foundation
import StackProtocols
@testable import StackConnect

/// Records everything `AnalyticsService` hands to a provider.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
final class MockAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {

    /// One entry per call, in order, to assert sequencing across methods.
    enum Call: Equatable {
        case send(String)
        case flush
        case reset
        case setCollectionEnabled(Bool)
    }

    private let lock = NSLock()
    private var _sentEvents: [AnalyticsEvent] = []
    private var _calls: [Call] = []

    var sentEvents: [AnalyticsEvent] { lock.withLock { _sentEvents } }
    var sentEventNames: [String] { sentEvents.map(\.name) }
    var calls: [Call] { lock.withLock { _calls } }
    var flushCount: Int { calls.filter { $0 == .flush }.count }
    var resetCount: Int { calls.filter { $0 == .reset }.count }
    var collectionEnabledCalls: [Bool] {
        calls.compactMap { call in
            if case .setCollectionEnabled(let enabled) = call { return enabled }
            return nil
        }
    }

    func send(_ event: AnalyticsEvent) {
        lock.withLock {
            _sentEvents.append(event)
            _calls.append(.send(event.name))
        }
    }

    func flush() async {
        lock.withLock { _calls.append(.flush) }
    }

    func reset() {
        lock.withLock { _calls.append(.reset) }
    }

    func setCollectionEnabled(_ enabled: Bool) {
        lock.withLock { _calls.append(.setCollectionEnabled(enabled)) }
    }
}
