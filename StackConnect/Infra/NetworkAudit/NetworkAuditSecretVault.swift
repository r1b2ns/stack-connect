import CryptoKit
import Foundation

/// Seals the original values of secret headers (`Authorization`, cookies…)
/// with AES-GCM before an audit event is written, using a 256-bit key kept in
/// the Keychain (device-only, readable after the first unlock so background
/// sync can still record).
///
/// The sealed box only lives inside the event file; the key never leaves the
/// Keychain. Deleting the whole log also drops the key (crypto-shredding of
/// anything a backup or a crash might have left behind).
protocol NetworkAuditSecretSealing: Sendable {
    func seal(_ secrets: [String: String]) -> Data?
    func open(_ sealed: Data) -> [String: String]?
    func destroyKey()
}

final class NetworkAuditSecretVault: NetworkAuditSecretSealing, @unchecked Sendable {

    static let keychainKey = "networkAudit.secretsKey"

    private let keychain: KeyStorable
    private let lock = NSLock()

    init(keychain: KeyStorable) {
        self.keychain = keychain
    }

    func seal(_ secrets: [String: String]) -> Data? {
        guard !secrets.isEmpty,
              let key = symmetricKey(createIfMissing: true),
              let plain = try? JSONEncoder().encode(secrets) else { return nil }
        do {
            return try AES.GCM.seal(plain, using: key).combined
        } catch {
            Log.print.error("[NetworkAudit] Failed to seal secrets: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func open(_ sealed: Data) -> [String: String]? {
        guard let key = symmetricKey(createIfMissing: false) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plain = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode([String: String].self, from: plain)
        } catch {
            Log.print.error("[NetworkAudit] Failed to open sealed secrets: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func destroyKey() {
        lock.lock()
        defer { lock.unlock() }
        keychain.removeObject(forKey: Self.keychainKey)
    }

    private func symmetricKey(createIfMissing: Bool) -> SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }
        if let data = keychain.data(forKey: Self.keychainKey), data.count == 32 {
            return SymmetricKey(data: data)
        }
        // Only create a key when the store says there is none: a locked
        // Keychain (`.unavailable`) must not get a second key that would make
        // the existing events unreadable.
        guard createIfMissing, keychain.presence(forKey: Self.keychainKey) == .missing else { return nil }
        let key = SymmetricKey(size: .bits256)
        keychain.set(key.withUnsafeBytes { Data($0) }, forKey: Self.keychainKey)
        return key
    }
}
