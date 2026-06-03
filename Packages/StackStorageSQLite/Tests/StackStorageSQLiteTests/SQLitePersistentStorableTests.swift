import XCTest
@testable import StackStorageSQLite

private struct Account: Codable, Hashable {
    let id: String
    let name: String
}

private struct Project: Codable, Hashable {
    let id: String
    let title: String
}

final class SQLitePersistentStorableTests: XCTestCase {

    private func makeInMemory() throws -> SQLitePersistentStorable {
        try SQLitePersistentStorable(path: ":memory:")
    }

    func testSaveAndFetch() async throws {
        let store = try makeInMemory()
        let account = Account(id: "1", name: "Acme")
        try await store.save(account, id: account.id)

        let fetched = try await store.fetch(Account.self, id: "1")
        XCTAssertEqual(fetched, account)
    }

    func testFetchMissingReturnsNil() async throws {
        let store = try makeInMemory()
        let fetched = try await store.fetch(Account.self, id: "missing")
        XCTAssertNil(fetched)
    }

    func testSaveOverwritesExisting() async throws {
        let store = try makeInMemory()
        try await store.save(Account(id: "1", name: "Old"), id: "1")
        try await store.save(Account(id: "1", name: "New"), id: "1")

        let fetched = try await store.fetch(Account.self, id: "1")
        XCTAssertEqual(fetched, Account(id: "1", name: "New"))

        let all = try await store.fetchAll(Account.self)
        XCTAssertEqual(all.count, 1)
    }

    func testFetchAll() async throws {
        let store = try makeInMemory()
        try await store.save(Account(id: "1", name: "A"), id: "1")
        try await store.save(Account(id: "2", name: "B"), id: "2")
        try await store.save(Account(id: "3", name: "C"), id: "3")

        let all = try await store.fetchAll(Account.self)
        XCTAssertEqual(Set(all), [
            Account(id: "1", name: "A"),
            Account(id: "2", name: "B"),
            Account(id: "3", name: "C"),
        ])
    }

    func testDelete() async throws {
        let store = try makeInMemory()
        try await store.save(Account(id: "1", name: "A"), id: "1")
        try await store.delete(Account.self, id: "1")

        let fetched = try await store.fetch(Account.self, id: "1")
        XCTAssertNil(fetched)
    }

    func testDeleteAll() async throws {
        let store = try makeInMemory()
        try await store.save(Account(id: "1", name: "A"), id: "1")
        try await store.save(Account(id: "2", name: "B"), id: "2")
        try await store.deleteAll(Account.self)

        let all = try await store.fetchAll(Account.self)
        XCTAssertTrue(all.isEmpty)
    }

    func testTypesAreIsolated() async throws {
        let store = try makeInMemory()
        try await store.save(Account(id: "1", name: "A"), id: "1")
        try await store.save(Project(id: "1", title: "P"), id: "1")

        let account = try await store.fetch(Account.self, id: "1")
        let project = try await store.fetch(Project.self, id: "1")
        let accountCount = try await store.fetchAll(Account.self).count
        let projectCount = try await store.fetchAll(Project.self).count

        XCTAssertEqual(account, Account(id: "1", name: "A"))
        XCTAssertEqual(project, Project(id: "1", title: "P"))
        XCTAssertEqual(accountCount, 1)
        XCTAssertEqual(projectCount, 1)
    }

    func testPersistenceAcrossReopen() async throws {
        let path = NSTemporaryDirectory() + "stackconnect-sqlite-test-\(ProcessInfo.processInfo.globallyUniqueString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let store = try SQLitePersistentStorable(path: path)
            try await store.save(Account(id: "1", name: "Persisted"), id: "1")
        }

        let reopened = try SQLitePersistentStorable(path: path)
        let fetched = try await reopened.fetch(Account.self, id: "1")
        XCTAssertEqual(fetched, Account(id: "1", name: "Persisted"))
    }
}
