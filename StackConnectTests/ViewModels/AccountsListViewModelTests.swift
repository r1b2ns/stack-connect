import XCTest
import StackProtocols
@testable import StackConnect

/// The unified accounts list (plan `unified-accounts.md` §2, Option A): one
/// group per store, the search, the statuses, delete and the re-import entry.
@MainActor
final class AccountsListViewModelTests: XCTestCase {

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

    private func makeSUT(featureFlags: FeatureFlags = .googlePlayOn) -> AccountsListViewModel {
        AccountsListViewModel(
            storage: storage,
            keychain: keychain,
            analytics: analytics,
            featureFlags: featureFlags,
            statusProvider: statuses,
            notificationCenter: NotificationCenter()
        )
    }

    private func save(_ accounts: AccountModel...) async throws {
        for account in accounts { try await storage.save(account, id: account.id) }
    }

    // MARK: - Grouping

    func testGroupsEveryStoreInListOrderWithAccountsByName() async throws {
        try await save(
            AccountModel(name: "Zeta", providerType: .firebase),
            AccountModel(name: "beta", providerType: .apple),
            AccountModel(name: "Play", providerType: .googlePlay),
            AccountModel(name: "Alpha", providerType: .apple)
        )
        let sut = makeSUT()

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.map(\.provider), [.apple, .googlePlay, .firebase])
        XCTAssertEqual(sut.uiState.groups.first?.accounts.map(\.name), ["Alpha", "beta"])
        XCTAssertEqual(sut.uiState.accounts.map(\.name), ["Alpha", "beta", "Play", "Zeta"])
        XCTAssertTrue(sut.uiState.hasLoaded)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    func testStoresWithoutAccountsHaveNoGroup() async throws {
        try await save(AccountModel(name: "Fire", providerType: .firebase))
        let sut = makeSUT()

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.map(\.provider), [.firebase])
    }

    func testGooglePlayIsHiddenWhileItsFlagIsOffAndNothingIsDeleted() async throws {
        try await save(AccountModel(id: "play", name: "Play", providerType: .googlePlay), AccountModel(name: "ASC", providerType: .apple))
        let sut = makeSUT(featureFlags: .googlePlayOff)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.map(\.provider), [.apple])
        let stored = try await storage.fetch(AccountModel.self, id: "play")
        XCTAssertNotNil(stored)
    }

    func testEmptyStateWithoutAccounts() async {
        let sut = makeSUT()

        await sut.loadAccounts()

        XCTAssertTrue(sut.uiState.accounts.isEmpty)
        XCTAssertTrue(sut.uiState.visibleGroups.isEmpty)
        XCTAssertFalse(sut.uiState.showsNoResults, "No accounts is the empty state, not an empty search")
    }

    func testPublishesTheStatusesOfItsAccounts() async throws {
        let account = AccountModel(name: "Personal", providerType: .apple, authMethod: .appleIdSignIn)
        try await save(account)
        statuses.statusesById = [account.id: .of(.signInExpired)]
        let sut = makeSUT()

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.accountStatuses[account.id]?.level, .disconnected)
    }

    // MARK: - Search

    private func loadedForSearch() async throws -> AccountsListViewModel {
        try await save(
            AccountModel(name: "Acme Apps", providerType: .apple),
            AccountModel(name: "Personal", providerType: .apple, authMethod: .appleIdSignIn),
            AccountModel(name: "Client North", providerType: .googlePlay, authMethod: .googleSignIn),
            AccountModel(name: "acme-prod", providerType: .firebase)
        )
        let sut = makeSUT()
        await sut.loadAccounts()
        return sut
    }

    func testSearchMatchesTheAccountName() async throws {
        let sut = try await loadedForSearch()

        sut.uiState.query = "acme"

        XCTAssertEqual(sut.uiState.visibleGroups.map(\.provider), [.apple, .firebase])
        XCTAssertEqual(sut.uiState.visibleGroups.flatMap(\.accounts).map(\.name), ["Acme Apps", "acme-prod"])
        XCTAssertEqual(sut.uiState.visibleCount, 2)
    }

    func testSearchMatchesTheStore() async throws {
        let sut = try await loadedForSearch()

        sut.uiState.query = "google play"

        XCTAssertEqual(sut.uiState.visibleGroups.flatMap(\.accounts).map(\.name), ["Client North"])
    }

    func testSearchMatchesHowTheAccountIsConnected() async throws {
        let sut = try await loadedForSearch()

        sut.uiState.query = AccountConnection(provider: .apple, kind: .signIn).title

        XCTAssertEqual(sut.uiState.visibleGroups.flatMap(\.accounts).map(\.name), ["Personal"])
    }

    func testSearchWithoutMatchesShowsTheNoResultsStateUntilCleared() async throws {
        let sut = try await loadedForSearch()

        sut.uiState.query = "nothing like this"
        XCTAssertTrue(sut.uiState.showsNoResults)
        XCTAssertTrue(sut.uiState.visibleGroups.isEmpty)

        sut.clearSearch()

        XCTAssertFalse(sut.uiState.showsNoResults)
        XCTAssertEqual(sut.uiState.visibleCount, 4)
    }

    func testABlankQueryKeepsEverything() async throws {
        let sut = try await loadedForSearch()

        sut.uiState.query = "   "

        XCTAssertFalse(sut.uiState.isSearching)
        XCTAssertEqual(sut.uiState.visibleCount, 4)
    }

    // MARK: - Delete

    func testDeleteAccountRemovesItsDataAndReloads() async throws {
        let deleted = AccountModel(name: "Old", providerType: .apple)
        let kept = AccountModel(name: "Kept", providerType: .apple)
        try await save(deleted, kept)
        keychain.set("secret", forKey: "credentials.\(deleted.id)")
        try await storage.save(ReplyTemplateModel(id: "t", accountId: deleted.id, title: "T", body: "B"), id: "t")
        let sut = makeSUT()
        await sut.loadAccounts()

        await sut.deleteAccount(deleted)

        XCTAssertEqual(sut.uiState.accounts.map(\.id), [kept.id])
        XCTAssertNil(keychain.string(forKey: "credentials.\(deleted.id)"))
        let templates = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertTrue(templates.isEmpty)
    }

    func testDeleteAccountTracksTapAndSuccess() async throws {
        let account = AccountModel(name: "ToDelete", providerType: .apple)
        try await save(account)
        let sut = makeSUT()

        await sut.deleteAccount(account)

        XCTAssertEqual(analytics.taps(of: .delete), [.buttonTap(.delete, on: .accountsList)])
        XCTAssertEqual(analytics.actions(of: .deleteAccount), [
            .action(.deleteAccount, on: .accountsList, result: .success, parameters: [
                AnalyticsParameterKey.kind: .string(ProviderType.apple.rawValue)
            ])
        ])
    }

    func testDeleteAccountTracksFailure() async throws {
        let account = AccountModel(name: "ToDelete", providerType: .apple)
        try await save(account)
        await storage.failDelete(AccountModel.self, id: account.id)
        let sut = makeSUT()

        await sut.deleteAccount(account)

        XCTAssertEqual(analytics.results(of: .deleteAccount), [.failure])
    }

    // MARK: - Re-import deep link

    func testReimportOpensTheWizardOnTheExpiredAccount() async throws {
        let expired = AccountModel(name: "Shared", providerType: .apple, origin: .imported, expirationDate: .distantPast)
        try await save(expired)
        let sut = makeSUT()

        let entry = await sut.reconnectEntry(forAccountId: expired.id)

        XCTAssertEqual(entry, .reconnect(expired))
    }

    func testReimportOfAHiddenOrMissingAccountDoesNothing() async throws {
        let play = AccountModel(name: "Play", providerType: .googlePlay, origin: .imported, expirationDate: .distantPast)
        try await save(play)
        let sut = makeSUT(featureFlags: .googlePlayOff)

        let hidden = await sut.reconnectEntry(forAccountId: play.id)
        let missing = await sut.reconnectEntry(forAccountId: "missing")

        XCTAssertNil(hidden)
        XCTAssertNil(missing)
    }
}
