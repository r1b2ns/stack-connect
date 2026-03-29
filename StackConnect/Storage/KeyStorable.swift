import Foundation

protocol KeyStorable {

    // MARK: - Read (primitives)

    func string(forKey key: String) -> String?
    func int(forKey key: String) -> Int?
    func double(forKey key: String) -> Double?
    func bool(forKey key: String) -> Bool?
    func data(forKey key: String) -> Data?

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

    func object<T: Decodable>(forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setObject<T: Encodable>(_ value: T, forKey key: String) {
        let data = try? JSONEncoder().encode(value)
        set(data, forKey: key)
    }
}
