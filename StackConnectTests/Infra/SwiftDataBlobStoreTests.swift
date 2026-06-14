import XCTest
import StackCore        // PersistentStorable
@testable import StackConnect

/// Unit tests for `SwiftDataBlobStore`, the sync `BlobStore` -> async
/// `PersistentStorable` bridge. Backed by an in-memory fake store so no real
/// SwiftData `ModelContainer` is spun up.
final class SwiftDataBlobStoreTests: XCTestCase {

    // MARK: - In-memory fake PersistentStorable

    /// Mirrors `SwiftDataStorable`'s behavior: derives the on-disk type name from
    /// `String(describing: T.self)` and stores the JSON payload keyed by
    /// typeName -> id. Implemented as an `actor` for Sendable-safe async access.
    private actor InMemoryStorable: PersistentStorable {
        private var store: [String: [String: Data]] = [:]
        private let encoder = JSONEncoder()
        private let decoder = JSONDecoder()

        private func typeName<T>(for type: T.Type) -> String {
            String(describing: type)
        }

        func save<T: Codable>(_ item: T, id: String) async throws {
            let name = typeName(for: T.self)
            guard let payload = try? encoder.encode(item) else {
                throw PersistentStorableError.encodingFailed
            }
            store[name, default: [:]][id] = payload
        }

        func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? {
            let name = typeName(for: type)
            guard let payload = store[name]?[id] else { return nil }
            guard let decoded = try? decoder.decode(T.self, from: payload) else {
                throw PersistentStorableError.decodingFailed
            }
            return decoded
        }

        func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
            let name = typeName(for: type)
            guard let bucket = store[name] else { return [] }
            return try bucket.values.compactMap { payload in
                guard let decoded = try? decoder.decode(T.self, from: payload) else {
                    throw PersistentStorableError.decodingFailed
                }
                return decoded
            }
        }

        func delete<T: Codable>(_ type: T.Type, id: String) async throws {
            let name = typeName(for: type)
            store[name]?[id] = nil
        }

        func deleteAll<T: Codable>(_ type: T.Type) async throws {
            let name = typeName(for: type)
            store[name] = nil
        }

        // Test-only introspection of the raw store.
        func count(forTypeName name: String) -> Int {
            store[name]?.count ?? 0
        }
    }

    // MARK: - Helpers

    private func makeSUT() -> (SwiftDataBlobStore, InMemoryStorable) {
        let storage = InMemoryStorable()
        let sut = SwiftDataBlobStore(storage: storage)
        return (sut, storage)
    }

    private func json(id: String, name: String, bundleId: String, platform: String?) -> String {
        let blob = CoreAppBlob(id: id, name: name, bundleId: bundleId, platform: platform)
        let data = try! JSONEncoder().encode(blob)
        return String(data: data, encoding: .utf8)!
    }

    private func decode(_ jsonString: String) -> CoreAppBlob {
        let data = jsonString.data(using: .utf8)!
        return try! JSONDecoder().decode(CoreAppBlob.self, from: data)
    }

    // MARK: - Tests

    func testSaveThenFetchRoundTripsAppBlob() {
        let (sut, _) = makeSUT()

        // non-nil platform
        sut.save(typeName: "app", id: "123", json: json(id: "123", name: "Stack", bundleId: "com.stack.app", platform: "IOS"))
        // nil platform
        sut.save(typeName: "app", id: "456", json: json(id: "456", name: "NoPlat", bundleId: "com.stack.noplat", platform: nil))

        let fetched123 = sut.fetch(typeName: "app", id: "123")
        XCTAssertNotNil(fetched123)
        XCTAssertEqual(
            decode(fetched123!),
            CoreAppBlob(id: "123", name: "Stack", bundleId: "com.stack.app", platform: "IOS")
        )

        let fetched456 = sut.fetch(typeName: "app", id: "456")
        XCTAssertNotNil(fetched456)
        XCTAssertEqual(
            decode(fetched456!),
            CoreAppBlob(id: "456", name: "NoPlat", bundleId: "com.stack.noplat", platform: nil)
        )
    }

    func testFetchAllReturnsAllSavedBlobs() {
        let (sut, _) = makeSUT()

        sut.save(typeName: "app", id: "1", json: json(id: "1", name: "One", bundleId: "com.one", platform: "IOS"))
        sut.save(typeName: "app", id: "2", json: json(id: "2", name: "Two", bundleId: "com.two", platform: "MAC_OS"))

        let all = sut.fetchAll(typeName: "app")
        XCTAssertEqual(all.count, 2)

        let decoded = all.map { decode($0) }.sorted { $0.id < $1.id }
        XCTAssertEqual(decoded, [
            CoreAppBlob(id: "1", name: "One", bundleId: "com.one", platform: "IOS"),
            CoreAppBlob(id: "2", name: "Two", bundleId: "com.two", platform: "MAC_OS"),
        ])
    }

    func testDeleteRemovesBlob() {
        let (sut, _) = makeSUT()

        sut.save(typeName: "app", id: "9", json: json(id: "9", name: "Gone", bundleId: "com.gone", platform: "IOS"))
        XCTAssertNotNil(sut.fetch(typeName: "app", id: "9"))

        sut.delete(typeName: "app", id: "9")

        XCTAssertNil(sut.fetch(typeName: "app", id: "9"))
        XCTAssertTrue(sut.fetchAll(typeName: "app").isEmpty)
    }

    func testUnknownTypeNameIsIgnored() async {
        let (sut, storage) = makeSUT()

        sut.save(typeName: "nope", id: "x", json: json(id: "x", name: "X", bundleId: "com.x", platform: nil))

        XCTAssertNil(sut.fetch(typeName: "nope", id: "x"))
        XCTAssertTrue(sut.fetchAll(typeName: "nope").isEmpty)

        // Nothing persisted under any bucket.
        let appCount = await storage.count(forTypeName: "CoreAppBlob")
        let nopeCount = await storage.count(forTypeName: "nope")
        XCTAssertEqual(appCount, 0)
        XCTAssertEqual(nopeCount, 0)
    }

    func testMalformedJsonIsIgnored() async {
        let (sut, storage) = makeSUT()

        sut.save(typeName: "app", id: "x", json: "not json")

        XCTAssertNil(sut.fetch(typeName: "app", id: "x"))
        XCTAssertTrue(sut.fetchAll(typeName: "app").isEmpty)

        let appCount = await storage.count(forTypeName: "CoreAppBlob")
        XCTAssertEqual(appCount, 0)
    }
}
