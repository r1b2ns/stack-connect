import Foundation

/// Whether a stored item exists, told apart from "can't be read right now".
enum KeyPresence: Equatable, Sendable {
    /// The item exists and was read.
    case present
    /// The store answered that no item exists for the key.
    case missing
    /// The store could not be read: the item may exist but is not reachable
    /// now (e.g. the Keychain while the device is locked, where reads of
    /// `WhenUnlocked` items fail with `errSecInteractionNotAllowed`). Callers
    /// must not treat this as missing.
    case unavailable
}

protocol KeyStorable {

    // MARK: - Read (primitives)

    func string(forKey key: String) -> String?
    func int(forKey key: String) -> Int?
    func double(forKey key: String) -> Double?
    func bool(forKey key: String) -> Bool?
    func data(forKey key: String) -> Data?

    // MARK: - Presence

    /// Whether an item exists for `key`, without mistaking an unreadable
    /// store for a missing item. Never returns or logs the value.
    func presence(forKey key: String) -> KeyPresence

    // MARK: - Read (Codable)

    func object<T: Decodable>(forKey key: String) -> T?

    // MARK: - Write (primitives)

    func set(_ value: Any?, forKey key: String)

    // MARK: - Write (Codable)

    func setObject<T: Encodable>(_ value: T, forKey key: String)

    // MARK: - Remove

    func removeObject(forKey key: String)
}

// MARK: - Default Codable Implementation

extension KeyStorable {

    /// Stores that can't fail to read (memory, `UserDefaults`) know an item is
    /// missing when `data(forKey:)` finds nothing.
    func presence(forKey key: String) -> KeyPresence {
        data(forKey: key) == nil ? .missing : .present
    }

    func object<T: Decodable>(forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setObject<T: Encodable>(_ value: T, forKey key: String) {
        let data = try? JSONEncoder().encode(value)
        set(data, forKey: key)
    }
}
