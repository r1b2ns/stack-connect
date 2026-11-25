import XCTest
import StackProtocols
@testable import StackConnect

/// Settings › Accounts (plan `unified-accounts.md` §4): the groups, the
/// search and "Delete all accounts", moved here from the Settings root.
@MainActor
final class SettingsAccountsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var statuses: MockAccountStatusProvider!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        statuses = MockAccountStatusProvider()
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        analytics = nil
        statuses = nil
        try await super.tearDown()
    }

    private func makeSUT(featureFlags: FeatureFlags = .googlePlayOn) -> SettingsAccountsViewModel {
        SettingsAccountsViewModel(
            storage: storage,
            keychain: keychain,
            analytics: analytics,
            featureFlags: featureFlags,
            statusProvider: statuses,
            notificationCenter: NotificationCenter()
        )
    }

    /// Seeds an account with its credentials, one app, one version and one reply template.
    private func seedAccount(_ account: AccountModel) async throws {
        try await storage.save(account, id: account.id)
        keychain.set("secret", forKey: "credentials.\(account.id)")
        let app = AppModel(id: "app-\(account.id)", name: "App", bundleId: "com.test.app", accountId: account.id)
        try await storage.save(app, id: "\(account.id).\(app.id)")
        let version = AppStoreVersionModel(id: "version-\(account.id)", appId: app.id)
        try await storage.save(version, id: "version.\(version.id)")
        let template = ReplyTemplateModel(id: "template-\(account.id)", accountId: account.id, title: "T", body: "B")
        try await storage.save(template, id: template.id)
    }

    // MARK: - Groups and search

    func testGroupsAreAppStoreConnectThenGooglePlayThenFirebase() async throws {
        for account in [
            AccountModel(name: "Fire", providerType: .firebase),
            AccountModel(name: "Play", providerType: .googlePlay),
            AccountModel(name: "Team", providerType: .apple)
        ] { try await storage.save(account, id: account.id) }
        let sut = makeSUT()

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.listing.groups.map(\.provider), [.apple, .googlePlay, .firebase])
    }

    func testHidesGooglePlayWhileItsFlagIsOff() async throws {
        try await storage.save(AccountModel(id: "play", name: "Play", providerType: .googlePlay), id: "play")
        try await storage.save(AccountModel(id: "asc", name: "ASC", providerType: .apple), id: "asc")
        let sut = makeSUT(featureFlags: .googlePlayOff)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.listing.groups.map(\.provider), [.apple])
        let stored = try await storage.fetch(AccountModel.self, id: "play")
        XCTAssertNotNil(stored, "A hidden account is never deleted")
    }

    func testSearchFiltersTheGroupsAndClears() async throws {
        try await storage.save(AccountModel(name: "Acme", providerType: .apple), id: "a")
        try await storage.save(AccountModel(name: "Fire", providerType: .firebase), id: "f")
        let sut = makeSUT()
        await sut.loadAccounts()

        sut.uiState.listing.query = "fire"
        XCTAssertEqual(sut.uiState.listing.visibleGroups.map(\.provider), [.firebase])

        sut.uiState.listing.query = "zzz"
        XCTAssertTrue(sut.uiState.listing.showsNoResults)

        sut.clearSearch()
        XCTAssertEqual(sut.uiState.listing.visibleCount, 2)
    }

    func testPublishesTheStatusesOfEveryStore() async throws {
        let apple = AccountModel(name: "Session", providerType: .apple, authMethod: .appleIdSignIn)
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        try await storage.save(apple, id: apple.id)
        try await storage.save(play, id: play.id)
        statuses.statusesById = [apple.id: .of(.signInExpired), play.id: .of(.accessExpiringSoon)]
        let sut = makeSUT()

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.listing.accountStatuses[apple.id]?.level, .disconnected)
        XCTAssertEqual(sut.uiState.listing.accountStatuses[play.id]?.level, .needsAttention)
    }

    func testReloadsOnAStatusChange() async throws {
        let account = AccountModel(name: "Team", providerType: .apple)
        let sut = makeSUT()
        await sut.loadAccounts()
        try await storage.save(account, id: account.id)

        statuses.sendChange()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sut.uiState.listing.accounts.map(\.id), [account.id])
    }

    // MARK: - Delete all accounts

    func testDeleteAllAccountsRemovesEveryAccountWithItsDataAndTemplates() async throws {
        let first = AccountModel(name: "First", providerType: .apple)
        let second = AccountModel(name: "Second", providerType: .firebase)
        try await seedAccount(first)
        try await seedAccount(second)
        let sut = makeSUT()

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
        XCTAssertTrue(sut.uiState.listing.accounts.isEmpty)
    }

    func testDeleteAllAccountsKeepsHiddenGooglePlayAccounts() async throws {
        let apple = AccountModel(name: "Apple", providerType: .apple)
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        try await seedAccount(apple)
        try await storage.save(play, id: play.id)
        let sut = makeSUT(featureFlags: .googlePlayOff)

        await sut.deleteAllAccounts()

        let accounts = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts.map(\.id), [play.id], "Only the accounts the user can see are deleted")
    }

    func testDeleteAllAccountsKeepsGoingWhenOneAccountFails() async throws {
        let failing = AccountModel(name: "Failing", providerType: .apple)
        let healthy = AccountModel(name: "Healthy", providerType: .apple)
        try await seedAccount(failing)
        try await seedAccount(healthy)
        await storage.failDelete(AccountModel.self, id: failing.id)
        let sut = makeSUT()

        await sut.deleteAllAccounts()

        let accounts = try await storage.fetchAll(AccountModel.self)
        let templates = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertEqual(accounts.map(\.id), [failing.id])
        XCTAssertFalse(templates.contains { $0.accountId == healthy.id })
        XCTAssertNil(keychain.string(forKey: "credentials.\(healthy.id)"))
        // The failing account keeps its credentials so it stays usable.
        XCTAssertEqual(keychain.string(forKey: "credentials.\(failing.id)"), "secret")
    }

    func testDeleteAllAccountsTracksConfirmTapAndSuccess() async throws {
        try await seedAccount(AccountModel(name: "First", providerType: .apple))
        let sut = makeSUT()

        await sut.deleteAllAccounts()

        XCTAssertEqual(analytics.taps(of: .confirmDeleteAllAccounts), [.buttonTap(.confirmDeleteAllAccounts, on: .settingsAccounts)])
        XCTAssertEqual(analytics.actions(of: .deleteAllAccounts), [
            .action(.deleteAllAccounts, on: .settingsAccounts, result: .success, parameters: [
                AnalyticsParameterKey.count: .int(1),
                AnalyticsParameterKey.failedCount: .int(0)
            ])
        ])
    }

    func testDeleteAllAccountsTracksFailureWhenFetchFails() async {
        await storage.failFetchAll(AccountModel.self)
        let sut = makeSUT()

        await sut.deleteAllAccounts()

        XCTAssertEqual(analytics.results(of: .deleteAllAccounts), [.failure])
    }

    func testDeleteAllAccountsTracksFailureWhenAnAccountFails() async throws {
        let failing = AccountModel(name: "Failing", providerType: .apple)
        try await seedAccount(failing)
        await storage.failDelete(AccountModel.self, id: failing.id)
        let sut = makeSUT()

        await sut.deleteAllAccounts()

        XCTAssertEqual(analytics.results(of: .deleteAllAccounts), [.failure])
    }
}
