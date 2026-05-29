import Foundation

public enum PersistentStorableError: Error, Equatable {
    case encodingFailed
    case decodingFailed
}

public protocol PersistentStorable: Sendable {

    // MARK: - Create / Update

    func save<T: Codable>(_ item: T, id: String) async throws

    // MARK: - Read

    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T?
    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T]

    /// Fetches all items previously stored under an explicit `typeName`, decoding
    /// them into `T`. Useful when the reading module (e.g. a widget extension)
    /// wants to decode into a focused DTO that differs from the type name the
    /// writer used.
    func fetchAll<T: Codable>(_ type: T.Type, typeName: String) async throws -> [T]

    /// Fetches a single item stored under an explicit `typeName` and `id`,
    /// decoding into `T`. Mirror of `fetch(_:id:)` for cross-module DTO reads.
    func fetch<T: Codable>(_ type: T.Type, id: String, typeName: String) async throws -> T?

    // MARK: - Delete

    func delete<T: Codable>(_ type: T.Type, id: String) async throws
    func deleteAll<T: Codable>(_ type: T.Type) async throws
}

public extension PersistentStorable {

    /// Default implementation derives the stored type name from `T`.
    func fetchAll<T: Codable>(_ type: T.Type, typeName: String) async throws -> [T] {
        try await fetchAll(type)
    }

    /// Default implementation derives the stored type name from `T`.
    func fetch<T: Codable>(_ type: T.Type, id: String, typeName: String) async throws -> T? {
        try await fetch(type, id: id)
    }
}
