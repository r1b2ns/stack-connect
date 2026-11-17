#if DEBUG
import Foundation

/// In-memory `KeyStorable` used instead of the Keychain in fake data mode.
///
/// Values are stored as `Data` exactly like `KeychainStorable` encodes them, so
/// every typed read (`string`, `int`, `bool`, `object`) behaves the same. Nothing
/// is persisted: the seeded credentials are written again on every launch.
final class FakeKeyStorable: KeyStorable, @unchecked Sendable {

    private let lock = NSLock()
    private var values: [String: Data] = [:]

    init() {}

    /// Every key currently stored (for tests and debugging).
    var keys: [String] {
        lock.withLock { Array(values.keys) }
    }

    // MARK: - Read

    func string(forKey key: String) -> String? {
        data(forKey: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    func int(forKey key: String) -> Int? {
        guard let data = data(forKey: key), data.count == MemoryLayout<Int>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
    }

    func double(forKey key: String) -> Double? {
        guard let data = data(forKey: key), data.count == MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
    }

    func bool(forKey key: String) -> Bool? {
        guard let data = data(forKey: key), data.count == 1 else { return nil }
        return data[0] != 0
    }

    func data(forKey key: String) -> Data? {
        lock.withLock { values[key] }
    }

    // MARK: - Write

    func set(_ value: Any?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }
        let encoded: Data?
        switch value {
        case let string as String: encoded = string.data(using: .utf8)
        case let int as Int:       encoded = withUnsafeBytes(of: int) { Data($0) }
        case let double as Double: encoded = withUnsafeBytes(of: double) { Data($0) }
        case let bool as Bool:     encoded = Data([bool ? 1 : 0])
        case let data as Data:     encoded = data
        default:
            Log.print.warning("[FakeData] Unsupported value type '\(String(describing: type(of: value)))' for key '\(key)'")
            encoded = nil
        }
        guard let encoded else { return }
        lock.withLock { values[key] = encoded }
    }

    func removeObject(forKey key: String) {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}
#endif
