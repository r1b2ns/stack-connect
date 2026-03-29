import Foundation

enum PersistentStorableError: Error, Equatable {
    case encodingFailed
    case decodingFailed
}

protocol PersistentStorable {

    // MARK: - Create / Update

    func save<T: Codable>(_ item: T, id: String) async throws

    // MARK: - Read

    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T?
    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T]

    // MARK: - Delete

    func delete<T: Codable>(_ type: T.Type, id: String) async throws
    func deleteAll<T: Codable>(_ type: T.Type) async throws
}
