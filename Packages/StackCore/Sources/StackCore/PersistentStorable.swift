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

    // MARK: - Delete

    func delete<T: Codable>(_ type: T.Type, id: String) async throws
    func deleteAll<T: Codable>(_ type: T.Type) async throws
}

// NOTE: The explicit-`typeName` reads (used by the widget extension to decode
// the app's payloads into focused DTOs) are intentionally NOT protocol
// requirements. They live as concrete methods on `SwiftDataStorable`. Declaring
// them on the protocol with a default implementation caused calls on the
// concrete type to mis-dispatch to the default (which derives the type name from
// `T`), silently returning nothing — e.g. the widget failing to read phased
// releases. Keeping them concrete-only makes dispatch unambiguous.
