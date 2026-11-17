import Foundation

/// Thread-safe Bool a `@Sendable` mock handler can read and set (e.g. to make a
/// call fail until the test flips it, or to record what the handler saw).
final class LockedFlag: @unchecked Sendable {

    private let lock = NSLock()
    private var _value = false

    var value: Bool { lock.withLock { _value } }

    func set(_ newValue: Bool) {
        lock.withLock { _value = newValue }
    }
}
