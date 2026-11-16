import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AccountManagementViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var sut: AccountManagementViewModel!

    private let account = AccountModel(name: "Managed", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        sut = AccountManagementViewModel(account: account, storage: storage, keychain: keychain, analytics: analytics)

        try await storage.save(account, id: account.id)
        keychain.set("secret", forKey: "credentials.\(account.id)")
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
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

    // MARK: - Analytics events

    func testDeleteAccountTracksConfirmTapAndSuccess() async {
        _ = await sut.deleteAccount()

        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .accountManagement)])
        XCTAssertEqual(analytics.actions(of: .deleteAccount), [
            .action(.deleteAccount, on: .accountManagement, result: .success, parameters: [
                AnalyticsParameterKey.kind: .string(ProviderType.apple.rawValue)
            ])
        ])
    }

    func testDeleteAccountTracksFailure() async {
        await storage.failDelete(AccountModel.self, id: account.id)

        _ = await sut.deleteAccount()

        XCTAssertEqual(analytics.results(of: .deleteAccount), [.failure])
    }
}
