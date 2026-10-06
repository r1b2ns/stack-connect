import XCTest
@testable import StackConnect

@MainActor
final class SettingsViewModelTests: XCTestCase {

    private func makeSUT(
        storage: MockPersistentStorable = MockPersistentStorable(),
        keychain: MockKeyStorable = MockKeyStorable()
    ) -> (SettingsViewModel, AppSettings, UserDefaults, String) {
        let suite = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let appSettings = AppSettings(defaults: defaults)
        let sut = SettingsViewModel(
            storage: storage,
            keychain: keychain,
            appSettings: appSettings
        )
        return (sut, appSettings, defaults, suite)
    }

    func testPreReviewChecklistDefaultsToEnabled() {
        let (sut, _, defaults, suite) = makeSUT()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(sut.uiState.preReviewChecklistEnabled)
    }

    func testTogglePersistsToAppSettings() {
        let (sut, appSettings, defaults, suite) = makeSUT()
        defer { defaults.removePersistentDomain(forName: suite) }

        sut.setPreReviewChecklistEnabled(false)

        XCTAssertFalse(sut.uiState.preReviewChecklistEnabled)
        XCTAssertFalse(appSettings.isEnabled(.preReviewChecklistEnabled))
    }

    // MARK: - Delete all accounts

    /// Seeds an account with its credentials, one app, one version and one reply template.
    private func seedAccount(
        _ account: AccountModel,
        storage: MockPersistentStorable,
        keychain: MockKeyStorable
    ) async throws {
        try await storage.save(account, id: account.id)
        keychain.set("secret", forKey: "credentials.\(account.id)")
        let app = AppModel(id: "app-\(account.id)", name: "App", bundleId: "com.test.app", accountId: account.id)
        try await storage.save(app, id: "\(account.id).\(app.id)")
        let version = AppStoreVersionModel(id: "version-\(account.id)", appId: app.id)
        try await storage.save(version, id: "version.\(version.id)")
        let template = ReplyTemplateModel(id: "template-\(account.id)", accountId: account.id, title: "T", body: "B")
        try await storage.save(template, id: template.id)
    }

    func testDeleteAllAccountsRemovesEveryAccountWithItsDataAndTemplates() async throws {
        let storage = MockPersistentStorable()
        let keychain = MockKeyStorable()
        let (sut, _, defaults, suite) = makeSUT(storage: storage, keychain: keychain)
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AccountModel(name: "First", providerType: .apple)
        let second = AccountModel(name: "Second", providerType: .firebase)
        try await seedAccount(first, storage: storage, keychain: keychain)
        try await seedAccount(second, storage: storage, keychain: keychain)

        await sut.deleteAllAccounts()

        let accounts = try await storage.fetchAll(AccountModel.self)
        let apps = try await storage.fetchAll(AppModel.self)
        let versions = try await storage.fetchAll(AppStoreVersionModel.self)
        let templates = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertTrue(apps.isEmpty)
        XCTAssertTrue(versions.isEmpty)
        XCTAssertTrue(templates.isEmpty)
        XCTAssertNil(keychain.string(forKey: "credentials.\(first.id)"))
        XCTAssertNil(keychain.string(forKey: "credentials.\(second.id)"))
    }

    func testDeleteAllAccountsKeepsGoingWhenOneAccountFails() async throws {
        let storage = MockPersistentStorable()
        let keychain = MockKeyStorable()
        let (sut, _, defaults, suite) = makeSUT(storage: storage, keychain: keychain)
        defer { defaults.removePersistentDomain(forName: suite) }
        let failing = AccountModel(name: "Failing", providerType: .apple)
        let healthy = AccountModel(name: "Healthy", providerType: .apple)
        try await seedAccount(failing, storage: storage, keychain: keychain)
        try await seedAccount(healthy, storage: storage, keychain: keychain)
        await storage.failDelete(AccountModel.self, id: failing.id)

        await sut.deleteAllAccounts()

        // The healthy account is fully removed regardless of iteration order.
        let accounts = try await storage.fetchAll(AccountModel.self)
        let templates = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertEqual(accounts.map(\.id), [failing.id])
        XCTAssertFalse(templates.contains { $0.accountId == healthy.id })
        XCTAssertNil(keychain.string(forKey: "credentials.\(healthy.id)"))
        // The failing account keeps its credentials so it stays usable.
        XCTAssertEqual(keychain.string(forKey: "credentials.\(failing.id)"), "secret")
    }
}
