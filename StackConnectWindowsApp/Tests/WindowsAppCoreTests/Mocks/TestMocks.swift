import Foundation
import StackProtocols

// MARK: - Shared Test Mocks

/// In-memory mock for `PersistentStorable` that tracks call counts per type.
/// All access is serialized through `@MainActor` (test class annotation), so no
/// locking is needed.
final class MockStorage: PersistentStorable, @unchecked Sendable {
    private var store: [String: Data] = [:]

    var shouldThrowOnFetch = false
    var shouldThrowOnSave = false
    var shouldThrowOnDelete = false
    private(set) var fetchAllCallCount: [String: Int] = [:]

    func save<T: Codable>(_ item: T, id: String) async throws {
        if shouldThrowOnSave { throw PersistentStorableError.encodingFailed }
        let data = try JSONEncoder().encode(item)
        store["\(String(describing: T.self)).\(id)"] = data
    }

    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? {
        if shouldThrowOnFetch { throw PersistentStorableError.decodingFailed }
        guard let data = store["\(String(describing: T.self)).\(id)"] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
        if shouldThrowOnFetch { throw PersistentStorableError.decodingFailed }
        let key = String(describing: T.self)
        fetchAllCallCount[key, default: 0] += 1
        let datas = store.filter { $0.key.hasPrefix("\(key).") }.values
        return try datas.map { try JSONDecoder().decode(T.self, from: $0) }
    }

    func delete<T: Codable>(_ type: T.Type, id: String) async throws {
        if shouldThrowOnDelete { throw PersistentStorableError.decodingFailed }
        store["\(String(describing: T.self)).\(id)"] = nil
    }

    func deleteAll<T: Codable>(_ type: T.Type) async throws {
        if shouldThrowOnDelete { throw PersistentStorableError.decodingFailed }
        let prefix = "\(String(describing: T.self))."
        for key in store.keys where key.hasPrefix(prefix) { store[key] = nil }
    }
}

/// In-memory mock for `KeyStorable`.
final class MockSecrets: KeyStorable {
    private var store: [String: Any] = [:]

    func string(forKey key: String) -> String? { store[key] as? String }
    func int(forKey key: String) -> Int? { store[key] as? Int }
    func double(forKey key: String) -> Double? { store[key] as? Double }
    func bool(forKey key: String) -> Bool? { store[key] as? Bool }
    func data(forKey key: String) -> Data? { store[key] as? Data }

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
