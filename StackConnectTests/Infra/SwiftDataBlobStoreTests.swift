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

        // Test-only direct read of a persisted AppModel (the adapter now stores
        // AppModel under composite keys, not CoreAppBlob).
        func appModel(id: String) -> AppModel? {
            guard let payload = store["AppModel"]?[id] else { return nil }
            return try? decoder.decode(AppModel.self, from: payload)
        }

        // Test-only seeding of a full AppModel, exactly as the app persists it.
        func seedAppModel(_ model: AppModel, id: String) {
            guard let payload = try? encoder.encode(model) else { return }
            store["AppModel", default: [:]][id] = payload
        }
    }

    // MARK: - Helpers

    private func makeSUT() -> (SwiftDataBlobStore, InMemoryStorable) {
        let storage = InMemoryStorable()
        let sut = SwiftDataBlobStore(storage: storage)
        return (sut, storage)
    }

    private func json(id: String, name: String, bundleId: String, platform: String?, accountId: String) -> String {
        let blob = CoreAppBlob(id: id, name: name, bundleId: bundleId, platform: platform, accountId: accountId)
        let data = try! JSONEncoder().encode(blob)
        return String(data: data, encoding: .utf8)!
    }

    private func decode(_ jsonString: String) -> CoreAppBlob {
        let data = jsonString.data(using: .utf8)!
        return try! JSONDecoder().decode(CoreAppBlob.self, from: data)
    }

    // MARK: - Tests

    /// `save("app", appId, base blob)` creates an `AppModel` at the composite key
    /// "<accountId>.<appId>" with the base fields and default enrichment fields.
    func testSaveCreatesAppModelAtCompositeKeyWithDefaults() async {
        let (sut, storage) = makeSUT()

        // non-nil platform
        sut.save(typeName: "app", id: "123", json: json(id: "123", name: "Stack", bundleId: "com.stack.app", platform: "IOS", accountId: "acct"))
        // nil platform
        sut.save(typeName: "app", id: "456", json: json(id: "456", name: "NoPlat", bundleId: "com.stack.noplat", platform: nil, accountId: "acct"))

        let app123 = await storage.appModel(id: "acct.123")
        XCTAssertNotNil(app123)
        XCTAssertEqual(app123?.id, "123")
        XCTAssertEqual(app123?.name, "Stack")
        XCTAssertEqual(app123?.bundleId, "com.stack.app")
        XCTAssertEqual(app123?.platform, "IOS")
        XCTAssertEqual(app123?.accountId, "acct")
        // Enrichment / user fields default for a brand-new app.
        XCTAssertNil(app123?.iconUrl)
        XCTAssertNil(app123?.appStoreState)
        XCTAssertNil(app123?.versionString)
        XCTAssertNil(app123?.lastModifiedDate)
        XCTAssertEqual(app123?.isArchived, false)
        XCTAssertEqual(app123?.isFavorite, false)
        XCTAssertEqual(app123?.hasReviewPending, false)
        XCTAssertNil(app123?.platformVersions)

        let app456 = await storage.appModel(id: "acct.456")
        XCTAssertEqual(app456?.platform, nil)
        XCTAssertEqual(app456?.bundleId, "com.stack.noplat")
    }

    /// A save must MERGE the core's base fields into an existing `AppModel`,
    /// preserving enrichment/user fields (regression guard: never drop
    /// iconUrl/isFavorite/etc. on sync).
    func testSaveMergesIntoExistingAppModelPreservingEnrichment() async {
        let (sut, storage) = makeSUT()

        // Seed an existing enriched AppModel at the composite key.
        let existing = AppModel(
            id: "123",
            name: "Old Name",
            bundleId: "com.old.bundle",
            platform: "IOS",
            accountId: "acct",
            iconUrl: "https://cdn/icon.png",
            appStoreState: .readyForSale,
            versionString: "1.4.2",
            lastModifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            isArchived: false,
            isFavorite: true,
            hasReviewPending: true,
            platformVersions: [AppPlatformVersion(platform: "IOS", appStoreState: .readyForSale, versionString: "1.4.2")]
        )
        await storage.seedAppModel(existing, id: "acct.123")

        // Save a base blob with CHANGED name + bundleId (authoritative base fields).
        sut.save(typeName: "app", id: "123", json: json(id: "123", name: "New Name", bundleId: "com.new.bundle", platform: "MAC_OS", accountId: "acct"))

        let merged = await storage.appModel(id: "acct.123")
        XCTAssertNotNil(merged)
        // Base fields come from the core blob.
        XCTAssertEqual(merged?.name, "New Name")
        XCTAssertEqual(merged?.bundleId, "com.new.bundle")
        XCTAssertEqual(merged?.platform, "MAC_OS")
        XCTAssertEqual(merged?.id, "123")
        XCTAssertEqual(merged?.accountId, "acct")
        // Enrichment / user fields are preserved.
        XCTAssertEqual(merged?.iconUrl, "https://cdn/icon.png")
        XCTAssertEqual(merged?.appStoreState, .readyForSale)
        XCTAssertEqual(merged?.versionString, "1.4.2")
        XCTAssertEqual(merged?.lastModifiedDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(merged?.isFavorite, true)
        XCTAssertEqual(merged?.hasReviewPending, true)
        XCTAssertEqual(merged?.platformVersions?.first?.versionString, "1.4.2")
    }

    /// `fetch("app", compositeId)` re-emits the AppModel as the core's base blob JSON.
    func testFetchReturnsBaseBlobForCompositeKey() {
        let (sut, _) = makeSUT()

        sut.save(typeName: "app", id: "123", json: json(id: "123", name: "Stack", bundleId: "com.stack.app", platform: "IOS", accountId: "acct"))

        let fetched = sut.fetch(typeName: "app", id: "acct.123")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(
            decode(fetched!),
            CoreAppBlob(id: "123", name: "Stack", bundleId: "com.stack.app", platform: "IOS", accountId: "acct")
        )

        XCTAssertNil(sut.fetch(typeName: "app", id: "acct.999"))
    }

    /// `fetchAll("app")` returns base JSON for all AppModels.
    func testFetchAllReturnsBaseBlobsForAllAppModels() {
        let (sut, _) = makeSUT()

        sut.save(typeName: "app", id: "1", json: json(id: "1", name: "One", bundleId: "com.one", platform: "IOS", accountId: "acct"))
        sut.save(typeName: "app", id: "2", json: json(id: "2", name: "Two", bundleId: "com.two", platform: "MAC_OS", accountId: "acct"))

        let all = sut.fetchAll(typeName: "app")
        XCTAssertEqual(all.count, 2)

        let decoded = all.map { decode($0) }.sorted { $0.id < $1.id }
        XCTAssertEqual(decoded, [
            CoreAppBlob(id: "1", name: "One", bundleId: "com.one", platform: "IOS", accountId: "acct"),
            CoreAppBlob(id: "2", name: "Two", bundleId: "com.two", platform: "MAC_OS", accountId: "acct"),
        ])
    }

    /// `delete("app", compositeId)` removes the matching AppModel.
    func testDeleteRemovesAppModelByCompositeKey() {
        let (sut, _) = makeSUT()

        sut.save(typeName: "app", id: "9", json: json(id: "9", name: "Gone", bundleId: "com.gone", platform: "IOS", accountId: "acct"))
        XCTAssertNotNil(sut.fetch(typeName: "app", id: "acct.9"))

        sut.delete(typeName: "app", id: "acct.9")

        XCTAssertNil(sut.fetch(typeName: "app", id: "acct.9"))
        XCTAssertTrue(sut.fetchAll(typeName: "app").isEmpty)
    }

    func testUnknownTypeNameIsIgnored() async {
        let (sut, storage) = makeSUT()

        sut.save(typeName: "nope", id: "x", json: json(id: "x", name: "X", bundleId: "com.x", platform: nil, accountId: "acct"))

        XCTAssertNil(sut.fetch(typeName: "nope", id: "x"))
        XCTAssertTrue(sut.fetchAll(typeName: "nope").isEmpty)

        // Nothing persisted under any bucket.
        let appCount = await storage.count(forTypeName: "AppModel")
        let nopeCount = await storage.count(forTypeName: "nope")
        XCTAssertEqual(appCount, 0)
        XCTAssertEqual(nopeCount, 0)
    }

    func testMalformedJsonIsIgnored() async {
        let (sut, storage) = makeSUT()

        sut.save(typeName: "app", id: "x", json: "not json")

        XCTAssertTrue(sut.fetchAll(typeName: "app").isEmpty)

        let appCount = await storage.count(forTypeName: "AppModel")
        XCTAssertEqual(appCount, 0)
    }
}
