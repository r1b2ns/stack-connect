import Foundation
@testable import StackConnect

actor MockPersistentStorable: PersistentStorable {

    private var store: [String: [String: Data]] = [:]

    func save<T: Codable>(_ item: T, id: String) throws {
        let typeName = String(describing: T.self)
        guard let data = try? JSONEncoder().encode(item) else {
            throw PersistentStorableError.encodingFailed
        }
        if store[typeName] == nil {
            store[typeName] = [:]
        }
        store[typeName]?[id] = data
    }

    func fetch<T: Codable>(_ type: T.Type, id: String) throws -> T? {
        let typeName = String(describing: T.self)
        guard let data = store[typeName]?[id] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func fetchAll<T: Codable>(_ type: T.Type) throws -> [T] {
        let typeName = String(describing: T.self)
        guard let entries = store[typeName] else { return [] }
        return entries.values.compactMap { data in
            try? JSONDecoder().decode(T.self, from: data)
        }
    }

    func delete<T: Codable>(_ type: T.Type, id: String) throws {
        let typeName = String(describing: T.self)
        store[typeName]?.removeValue(forKey: id)
    }

    func deleteAll<T: Codable>(_ type: T.Type) throws {
        let typeName = String(describing: T.self)
        store.removeValue(forKey: typeName)
    }
}
