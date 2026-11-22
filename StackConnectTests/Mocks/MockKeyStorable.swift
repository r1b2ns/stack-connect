import Foundation
@testable import StackConnect

final class MockKeyStorable: KeyStorable {

    private var store: [String: Any] = [:]

    /// Every key currently stored — lets tests assert nothing was written.
    var storedKeys: Set<String> {
        Set(store.keys)
    }

    func string(forKey key: String) -> String? {
        store[key] as? String
    }

    func int(forKey key: String) -> Int? {
        store[key] as? Int
    }

    func double(forKey key: String) -> Double? {
        store[key] as? Double
    }

    func bool(forKey key: String) -> Bool? {
        store[key] as? Bool
    }

    func data(forKey key: String) -> Data? {
        store[key] as? Data
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
