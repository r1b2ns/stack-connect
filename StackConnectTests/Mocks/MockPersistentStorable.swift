import Foundation
@testable import StackConnect

actor MockPersistentStorable: PersistentStorable {

    /// Error thrown by operations configured through the failure-injection API.
    struct InjectedFailure: Error {}

    private var store: [String: [String: Data]] = [:]
    private(set) var fetchAllCallCount: [String: Int] = [:]
    /// Successful `save` calls per stored type name (`String(describing: T.self)`).
    private(set) var saveCallCount: [String: Int] = [:]
    private var failingFetchAllTypes: Set<String> = []
    private var failingDeletes: Set<String> = []

    // MARK: - Failure injection

    /// Makes every subsequent `fetchAll` of `type` throw `InjectedFailure`.
    func failFetchAll<T>(_ type: T.Type) {
        failingFetchAllTypes.insert(String(describing: T.self))
    }

    /// Makes every subsequent `delete` of the `type` item stored under `id`
    /// throw `InjectedFailure` (the item stays stored).
    func failDelete<T>(_ type: T.Type, id: String) {
        failingDeletes.insert(Self.deleteKey(typeName: String(describing: T.self), id: id))
    }

    private static func deleteKey(typeName: String, id: String) -> String {
        "\(typeName)|\(id)"
    }

    // MARK: - PersistentStorable

    func save<T: Codable>(_ item: T, id: String) throws {
        let typeName = String(describing: T.self)
        guard let data = try? JSONEncoder().encode(item) else {
            throw PersistentStorableError.encodingFailed
        }
        if store[typeName] == nil {
            store[typeName] = [:]
        }
        store[typeName]?[id] = data
        saveCallCount[typeName, default: 0] += 1
    }

    func fetch<T: Codable>(_ type: T.Type, id: String) throws -> T? {
        let typeName = String(describing: T.self)
        guard let data = store[typeName]?[id] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func fetchAll<T: Codable>(_ type: T.Type) throws -> [T] {
        let typeName = String(describing: T.self)
        fetchAllCallCount[typeName, default: 0] += 1
        if failingFetchAllTypes.contains(typeName) { throw InjectedFailure() }
        guard let entries = store[typeName] else { return [] }
        return entries.values.compactMap { data in
            try? JSONDecoder().decode(T.self, from: data)
        }
    }

    func delete<T: Codable>(_ type: T.Type, id: String) throws {
        let typeName = String(describing: T.self)
        if failingDeletes.contains(Self.deleteKey(typeName: typeName, id: id)) { throw InjectedFailure() }
        store[typeName]?.removeValue(forKey: id)
    }

    func deleteAll<T: Codable>(_ type: T.Type) throws {
        let typeName = String(describing: T.self)
        store.removeValue(forKey: typeName)
    }
}
