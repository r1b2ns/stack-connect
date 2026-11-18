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
        case setUserProperty(name: String, value: String?)
        case recordNonFatal(domain: String, code: Int)
    }

    private let lock = NSLock()
    private var _sentEvents: [AnalyticsEvent] = []
    private var _calls: [Call] = []
    private var _nonFatals: [NSError] = []

    var sentEvents: [AnalyticsEvent] { lock.withLock { _sentEvents } }
    var sentEventNames: [String] { sentEvents.map(\.name) }
    var calls: [Call] { lock.withLock { _calls } }
    var nonFatals: [NSError] { lock.withLock { _nonFatals } }
    var flushCount: Int { calls.filter { $0 == .flush }.count }
    var resetCount: Int { calls.filter { $0 == .reset }.count }
    /// `setUserProperty` calls, in order.
    var userPropertyCalls: [(name: String, value: String?)] {
        calls.compactMap { call in
            if case .setUserProperty(let name, let value) = call { return (name, value) }
            return nil
        }
    }
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

    func recordNonFatal(_ error: NSError) {
        lock.withLock {
            _nonFatals.append(error)
            _calls.append(.recordNonFatal(domain: error.domain, code: error.code))
        }
    }

    func setUserProperty(_ value: String?, forName name: String) {
        lock.withLock { _calls.append(.setUserProperty(name: name, value: value)) }
    }
}
