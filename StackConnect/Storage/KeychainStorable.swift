import Foundation
import Security

/// `KeyStorable` over the iOS Keychain (generic-password items of one service).
///
/// **Accessibility.** Each key gets the class its `KeychainAccessibilityPolicy`
/// assigns (`.standard`: after first unlock, except the saved Apple ID
/// password, only while unlocked), always device-only and never synchronizable.
/// Every write sets it again, so an item written before the policy existed is
/// moved to its class on its next write (`KeychainAccessibilityMigration` moves
/// the others once).
///
/// **Writes while the Keychain can't be reached.** A write or delete that the
/// Keychain refuses with `errSecInteractionNotAllowed` (device locked, item
/// still `WhenUnlocked`, prewarm before first unlock) is never lost and never
/// retried as an add: it is kept in memory — the latest value per key wins, a
/// later delete cancels it — reads of that key in this process answer it, and
/// `flushPendingWrites()` replays it once the device unlocks
/// (`KeychainProtectedDataMaintenance`). It does not survive the process.
///
/// Thread-safe: used from many actors. One lock serializes the writes, deletes
/// and the pending queue (so per-key ordering holds); reads only take it to
/// look at the queue.
final class KeychainStorable: KeyStorable, @unchecked Sendable {

    // MARK: - Shared instance

    /// The key store every screen and service uses by default: the real Keychain.
    /// Typed as the `KeyStorable` abstraction so the DEBUG fake data mode can
    /// replace it with an in-memory store once, at launch, before anything reads
    /// it (`FakeDataBootstrap`) — the real Keychain is then never touched.
    nonisolated(unsafe) static var shared: KeyStorable = KeychainStorable()

    /// A write or delete the Keychain refused for now.
    enum PendingOperation: Equatable {
        case write(Data)
        case delete
    }

    // MARK: - Properties

    let service: String
    let accessibilityPolicy: KeychainAccessibilityPolicy
    let backend: any KeychainBackend

    private let lock = NSLock()
    private var pendingOperations: [String: PendingOperation] = [:]

    // MARK: - Init

    init(
        service: String = Bundle.main.bundleIdentifier ?? "app.stackconnect",
        accessibilityPolicy: KeychainAccessibilityPolicy = .standard,
        backend: any KeychainBackend = SecurityKeychainBackend()
    ) {
        self.service = service
        self.accessibilityPolicy = accessibilityPolicy
        self.backend = backend
    }

    // MARK: - Read (primitives)

    func string(forKey key: String) -> String? {
        guard let data = data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func int(forKey key: String) -> Int? {
        guard let data = data(forKey: key),
              data.count == MemoryLayout<Int>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Int.self) }
    }

    func double(forKey key: String) -> Double? {
        guard let data = data(forKey: key),
              data.count == MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Double.self) }
    }

    func bool(forKey key: String) -> Bool? {
        guard let data = data(forKey: key), data.count == 1 else { return nil }
        return data[0] != 0
    }

    func data(forKey key: String) -> Data? {
        if let pending = pendingOperation(forKey: key) {
            switch pending {
            case .write(let data): return data
            case .delete: return nil
            }
        }

        var query = itemQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, result) = backend.copyMatching(query)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Log.print.error("[Keychain] Read failed for key '\(key)': OSStatus \(status)")
            }
            return nil
        }

        return result as? Data
    }

    // MARK: - Presence

    func presence(forKey key: String) -> KeyPresence {
        if let pending = pendingOperation(forKey: key) {
            return pending == .delete ? .missing : .present
        }

        var query = itemQuery(forKey: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, _) = backend.copyMatching(query)
        return Self.presence(for: status, key: key)
    }

    /// Maps a `SecItemCopyMatching` result: only `errSecItemNotFound` means the
    /// item is gone. Anything else (notably `errSecInteractionNotAllowed` while
    /// the device is locked, at prewarm or in a background task) only means it
    /// can't be read now.
    static func presence(for status: OSStatus, key: String) -> KeyPresence {
        switch status {
        case errSecSuccess:
            return .present
        case errSecItemNotFound:
            return .missing
        default:
            Log.print.warning("[Keychain] Presence check unavailable for key '\(key)': OSStatus \(status)")
            return .unavailable
        }
    }

    // MARK: - Write (primitives)

    func set(_ value: Any?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }

        let encoded: Data?

        switch value {
        case let s as String:
            encoded = s.data(using: .utf8)
        case let i as Int:
            encoded = withUnsafeBytes(of: i) { Data($0) }
        case let d as Double:
            encoded = withUnsafeBytes(of: d) { Data($0) }
        case let b as Bool:
            encoded = Data([b ? 1 : 0])
        case let d as Data:
            encoded = d
        default:
            Log.print.warning("[Keychain] Unsupported value type '\(type(of: value))' for key '\(key)'.")
            return
        }

        guard let encoded else {
            Log.print.error("[Keychain] Encoding failed for key '\(key)'")
            return
        }

        persistData(encoded, forKey: key)
    }

    // MARK: - Remove

    func removeObject(forKey key: String) {
        lock.withLock {
            let status = deleteItem(forKey: key)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                pendingOperations[key] = nil
            case errSecInteractionNotAllowed:
                // Cancels a pending write of the key; replayed on unlock.
                pendingOperations[key] = .delete
                Log.print.warning("[Keychain] Delete deferred for key '\(key)' until the device unlocks: OSStatus \(status)")
            default:
                pendingOperations[key] = nil
                Log.print.error("[Keychain] Delete failed for key '\(key)': OSStatus \(status)")
            }
        }
    }

    // MARK: - Pending writes

    /// Whether writes or deletes wait for the device to unlock.
    var hasPendingOperations: Bool {
        lock.withLock { !pendingOperations.isEmpty }
    }

    /// The write or delete of `key` waiting for the device to unlock, if any.
    func pendingOperation(forKey key: String) -> PendingOperation? {
        lock.withLock { pendingOperations[key] }
    }

    /// Replays the writes and deletes the Keychain refused while the device was
    /// locked. Those still refused (`errSecInteractionNotAllowed`) stay queued;
    /// any other failure is logged and dropped. Returns how many stay queued.
    @discardableResult
    func flushPendingWrites() -> Int {
        lock.withLock {
            guard !pendingOperations.isEmpty else { return 0 }

            for (key, operation) in pendingOperations {
                let status: OSStatus
                switch operation {
                case .write(let data):
                    status = writeItem(data, forKey: key)
                case .delete:
                    let deleteStatus = deleteItem(forKey: key)
                    status = deleteStatus == errSecItemNotFound ? errSecSuccess : deleteStatus
                }

                switch status {
                case errSecSuccess:
                    pendingOperations[key] = nil
                    Log.print.info("[Keychain] Flushed pending operation for key '\(key)'")
                case errSecInteractionNotAllowed:
                    break
                default:
                    pendingOperations[key] = nil
                    Log.print.error("[Keychain] Flushing pending operation failed for key '\(key)': OSStatus \(status)")
                }
            }

            let remaining = pendingOperations.count
            if remaining > 0 {
                Log.print.warning("[Keychain] \(remaining) pending operation(s) still waiting for the device to unlock")
            }
            return remaining
        }
    }

    // MARK: - Private

    private func persistData(_ data: Data, forKey key: String) {
        lock.withLock {
            let status = writeItem(data, forKey: key)
            switch status {
            case errSecSuccess:
                pendingOperations[key] = nil
                Log.print.info("[Keychain] Saved key '\(key)'")
            case errSecInteractionNotAllowed:
                // Latest value wins; replayed on unlock, readable meanwhile.
                pendingOperations[key] = .write(data)
                Log.print.warning("[Keychain] Write deferred for key '\(key)' until the device unlocks: OSStatus \(status)")
            default:
                // An older pending value must not be replayed over this intent.
                pendingOperations[key] = nil
                Log.print.error("[Keychain] Write failed for key '\(key)': OSStatus \(status)")
            }
        }
    }

    /// Update first (value and accessibility class), add only when the item
    /// does not exist. Any other update failure — notably
    /// `errSecInteractionNotAllowed` — is returned as is: falling through to an
    /// add would fail too (duplicate) and lose the write. Caller holds `lock`.
    private func writeItem(_ data: Data, forKey key: String) -> OSStatus {
        let query = itemQuery(forKey: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibilityPolicy.accessibility(forKey: key).secValue
        ]

        let updateStatus = backend.update(query, attributes: attributes)
        guard updateStatus == errSecItemNotFound else { return updateStatus }

        let addStatus = backend.add(query.merging(attributes) { _, new in new })
        if addStatus == errSecDuplicateItem {
            // Created by someone else in between: update it after all.
            return backend.update(query, attributes: attributes)
        }
        return addStatus
    }

    /// Caller holds `lock`.
    private func deleteItem(forKey key: String) -> OSStatus {
        backend.delete(itemQuery(forKey: key))
    }

    private func itemQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
