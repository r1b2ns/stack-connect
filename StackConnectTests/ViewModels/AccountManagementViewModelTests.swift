import XCTest
@testable import StackConnect

@MainActor
final class AccountManagementViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var sut: AccountManagementViewModel!

    private let account = AccountModel(name: "Managed", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        sut = AccountManagementViewModel(account: account, storage: storage, keychain: keychain)

        try await storage.save(account, id: account.id)
        keychain.set("secret", forKey: "credentials.\(account.id)")
    }

    override func tearDown() async throws {
        sut = nil
        storage = nil
        keychain = nil
        try await super.tearDown()
    }

    func testDeleteAccountReturnsTrueAndRemovesAccountTemplatesAndCredentials() async throws {
        let mine = ReplyTemplateModel(id: "mine", accountId: account.id, title: "T", body: "B")
        let theirs = ReplyTemplateModel(id: "theirs", accountId: "another-account", title: "T", body: "B")
        try await storage.save(mine, id: mine.id)
        try await storage.save(theirs, id: theirs.id)

        let deleted = await sut.deleteAccount()

        let storedAccount = try await storage.fetch(AccountModel.self, id: account.id)
        let remainingTemplates = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertTrue(deleted)
        XCTAssertNil(storedAccount)
        XCTAssertEqual(remainingTemplates.map(\.id), ["theirs"])
        XCTAssertNil(keychain.string(forKey: "credentials.\(account.id)"))
    }

    func testDeleteAccountReturnsFalseWhenTheAccountRecordCannotBeDeleted() async throws {
        await storage.failDelete(AccountModel.self, id: account.id)

        let deleted = await sut.deleteAccount()

        let storedAccount = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertFalse(deleted)
        XCTAssertNotNil(storedAccount)
        XCTAssertEqual(keychain.string(forKey: "credentials.\(account.id)"), "secret")
    }
}
