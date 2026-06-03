import Foundation
import StackProtocols
import CSQLite

/// `sqlite3_bind_*` destructor sentinel telling SQLite to copy the bound bytes
/// immediately (so temporary buffers are safe). Not exposed as a Swift constant
/// because it is a `#define` casting `-1` to a function pointer.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteStorageError: Error, Equatable {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

/// `PersistentStorable` backed by a bundled SQLite database.
///
/// Cross-platform counterpart of `SwiftDataStorable`: same `(typeName, id)` →
/// JSON-blob model, so the app's storage abstraction works identically on
/// platforms without SwiftData (e.g. Windows).
///
/// Implemented as an `actor` so the SQLite connection is only ever touched
/// serially, which both satisfies `PersistentStorable: Sendable` and avoids
/// cross-thread access to the handle.
public actor SQLitePersistentStorable: PersistentStorable {

    private var db: OpaquePointer?

    /// Opens (creating if needed) a database at `path`. Use `":memory:"` for a
    /// transient in-memory database.
    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw SQLiteStorageError.openFailed(message)
        }
        self.db = handle
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Create / Update

    public func save<T: Codable>(_ item: T, id: String) throws {
        guard let payload = try? JSONEncoder().encode(item) else {
            throw PersistentStorableError.encodingFailed
        }

        let now = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO persisted_item (type_name, identifier, payload, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(type_name, identifier)
        DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at;
        """

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, typeName(for: T.self), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
        payload.withUnsafeBytes { buffer in
            sqlite3_bind_blob(stmt, 3, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_double(stmt, 4, now)
        sqlite3_bind_double(stmt, 5, now)

        try step(stmt)
    }

    // MARK: - Read

    public func fetch<T: Codable>(_ type: T.Type, id: String) throws -> T? {
        try fetch(type, id: id, typeName: typeName(for: type))
    }

    /// Reads a single payload using an explicit type name. Mirrors the
    /// concrete-only overload on `SwiftDataStorable` (used by the widget to decode
    /// the app's payloads into focused DTOs); deliberately not a protocol method.
    public func fetch<T: Codable>(_ type: T.Type, id: String, typeName name: String) throws -> T? {
        let sql = "SELECT payload FROM persisted_item WHERE type_name = ? AND identifier = ? LIMIT 1;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW, let data = columnBlob(stmt, 0) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw PersistentStorableError.decodingFailed
        }
        return decoded
    }

    public func fetchAll<T: Codable>(_ type: T.Type) throws -> [T] {
        try fetchAll(type, typeName: typeName(for: type))
    }

    /// Reads all payloads for an explicit type name. Undecodable rows are skipped,
    /// mirroring `SwiftDataStorable`'s lenient `fetchAll`.
    public func fetchAll<T: Codable>(_ type: T.Type, typeName name: String) throws -> [T] {
        let sql = "SELECT payload FROM persisted_item WHERE type_name = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let data = columnBlob(stmt, 0) else { continue }
            if let decoded = try? JSONDecoder().decode(T.self, from: data) {
                results.append(decoded)
            }
        }
        return results
    }

    // MARK: - Delete

    public func delete<T: Codable>(_ type: T.Type, id: String) throws {
        let sql = "DELETE FROM persisted_item WHERE type_name = ? AND identifier = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, typeName(for: type), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)

        try step(stmt)
    }

    public func deleteAll<T: Codable>(_ type: T.Type) throws {
        let sql = "DELETE FROM persisted_item WHERE type_name = ?;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, typeName(for: type), -1, SQLITE_TRANSIENT)

        try step(stmt)
    }

    // MARK: - Private

    private func typeName<T>(for type: T.Type) -> String {
        String(describing: type)
    }

    private func createSchema() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS persisted_item (
            type_name  TEXT NOT NULL,
            identifier TEXT NOT NULL,
            payload    BLOB NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (type_name, identifier)
        );
        """)
    }

    private func exec(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errmsg) == SQLITE_OK else {
            let message = errmsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errmsg)
            throw SQLiteStorageError.execFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(lastErrorMessage())
        }
        return stmt
    }

    private func step(_ stmt: OpaquePointer?) throws {
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteStorageError.stepFailed(lastErrorMessage())
        }
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard let ptr = sqlite3_column_blob(stmt, index) else {
            return count == 0 ? Data() : nil
        }
        return Data(bytes: ptr, count: count)
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "no database" }
        return String(cString: sqlite3_errmsg(db))
    }
}
