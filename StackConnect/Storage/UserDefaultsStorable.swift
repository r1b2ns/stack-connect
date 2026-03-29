import Foundation

final class UserDefaultsStorable: KeyStorable {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Read (primitives)

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func int(forKey key: String) -> Int? {
        defaults.object(forKey: key) != nil ? defaults.integer(forKey: key) : nil
    }

    func double(forKey key: String) -> Double? {
        defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : nil
    }

    func bool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : nil
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    // MARK: - Write (primitives)

    func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: - Remove

    func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
