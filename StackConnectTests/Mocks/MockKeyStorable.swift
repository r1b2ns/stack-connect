import Foundation
@testable import StackConnect

final class MockKeyStorable: KeyStorable {

    private var store: [String: Any] = [:]

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

    func set(_ value: Any?, forKey key: String) {
        if let value {
            store[key] = value
        } else {
            store.removeValue(forKey: key)
        }
    }

    func removeObject(forKey key: String) {
        store.removeValue(forKey: key)
    }
}
