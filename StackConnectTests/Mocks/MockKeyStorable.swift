import Foundation
@testable import StackConnect

final class MockKeyStorable: KeyStorable {

    private var store: [String: Any] = [:]

    /// Every key currently stored — lets tests assert nothing was written.
    var storedKeys: Set<String> {
        Set(store.keys)
    }

    /// Simulates a Keychain that can't be read now (device locked:
    /// `errSecInteractionNotAllowed`): every read returns `nil` and
    /// `presence(forKey:)` answers `.unavailable`, whatever is stored.
    var isUnavailable = false
    /// Like `isUnavailable`, for these keys only.
    var unavailableKeys: Set<String> = []

    private func isReadable(_ key: String) -> Bool {
        !isUnavailable && !unavailableKeys.contains(key)
    }

    func string(forKey key: String) -> String? {
        isReadable(key) ? store[key] as? String : nil
    }

    func int(forKey key: String) -> Int? {
        isReadable(key) ? store[key] as? Int : nil
    }

    func double(forKey key: String) -> Double? {
        isReadable(key) ? store[key] as? Double : nil
    }

    func bool(forKey key: String) -> Bool? {
        isReadable(key) ? store[key] as? Bool : nil
    }

    func data(forKey key: String) -> Data? {
        isReadable(key) ? store[key] as? Data : nil
    }

    func presence(forKey key: String) -> KeyPresence {
        guard isReadable(key) else { return .unavailable }
        return store[key] == nil ? .missing : .present
    }

    /// Every key written with a value, in order — lets tests tell a refresh
    /// (same value written again) from an untouched item.
    private(set) var writtenKeys: [String] = []

    func set(_ value: Any?, forKey key: String) {
        if let value {
            writtenKeys.append(key)
            store[key] = value
        } else {
            store.removeValue(forKey: key)
        }
    }

    func removeObject(forKey key: String) {
        store.removeValue(forKey: key)
    }
}
