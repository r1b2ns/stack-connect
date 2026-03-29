import XCTest
import SwiftData
@testable import StackConnect

final class SwiftDataStorableTests: XCTestCase {

    private var sut: SwiftDataStorable!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PersistedItem.self, configurations: config)
        sut = SwiftDataStorable(modelContainer: container)
    }

    override func tearDown() async throws {
        sut = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Save and Fetch

    func testSaveAndFetch() async throws {
        let account = AccountModel(name: "Test", providerType: .apple)
        try await sut.save(account, id: account.id)
        let fetched: AccountModel? = try await sut.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(fetched?.name, "Test")
        XCTAssertEqual(fetched?.providerType, .apple)
    }

    // MARK: - Fetch All

    func testFetchAll() async throws {
        let a1 = AccountModel(name: "Account 1", providerType: .apple)
        let a2 = AccountModel(name: "Account 2", providerType: .firebase)
        try await sut.save(a1, id: a1.id)
        try await sut.save(a2, id: a2.id)
        let all: [AccountModel] = try await sut.fetchAll(AccountModel.self)
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Update

    func testUpdate() async throws {
        let account = AccountModel(id: "fixed-id", name: "Original", providerType: .apple)
        try await sut.save(account, id: account.id)

        let updated = AccountModel(id: "fixed-id", name: "Updated", providerType: .apple)
        try await sut.save(updated, id: updated.id)

        let fetched: AccountModel? = try await sut.fetch(AccountModel.self, id: "fixed-id")
        XCTAssertEqual(fetched?.name, "Updated")
    }

    // MARK: - Delete

    func testDelete() async throws {
        let account = AccountModel(name: "ToDelete", providerType: .firebase)
        try await sut.save(account, id: account.id)
        try await sut.delete(AccountModel.self, id: account.id)
        let fetched: AccountModel? = try await sut.fetch(AccountModel.self, id: account.id)
        XCTAssertNil(fetched)
    }

    // MARK: - Delete All

    func testDeleteAll() async throws {
        let a1 = AccountModel(name: "A1", providerType: .apple)
        let a2 = AccountModel(name: "A2", providerType: .apple)
        try await sut.save(a1, id: a1.id)
        try await sut.save(a2, id: a2.id)
        try await sut.deleteAll(AccountModel.self)
        let all: [AccountModel] = try await sut.fetchAll(AccountModel.self)
        XCTAssertTrue(all.isEmpty)
    }
}
