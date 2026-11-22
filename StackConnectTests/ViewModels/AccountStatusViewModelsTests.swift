import Combine
import XCTest
import StackProtocols
@testable import StackConnect

/// The account status chips of the accounts lists, the notice of the apps
/// lists and the chips of the mixed Home rows: each screen publishes what
/// `AccountStatusProviding` / `AccountStatusResolving` says and refreshes on
/// a change. Asserts state, never translated text.
@MainActor
final class AccountStatusViewModelsTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var provider: MockAccountStatusProvider!
    private var analytics: MockAnalyticsTracker!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        provider = MockAccountStatusProvider()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        provider = nil
        analytics = nil
        try await super.tearDown()
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
    }

    @discardableResult
    private func saveAccount(_ name: String, provider type: ProviderType = .apple) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: type)
        try await storage.save(account, id: account.id)
        return account
    }

    // MARK: - Accounts list

    func testAccountsListPublishesStatusesOfItsAccounts() async throws {
        let ok = try await saveAccount("OK")
        let broken = try await saveAccount("Broken")
        let pending = try await saveAccount("Pending")
        provider.statusesById = [broken.id: .of(.signInExpired), pending.id: .of(.pendingAgreements)]
        let sut = AccountsListViewModel(providerType: .apple, storage: storage, keychain: keychain, analytics: analytics, statusProvider: provider)

        await sut.loadAccounts()

        XCTAssertNil(sut.uiState.accountStatuses[ok.id])
        XCTAssertEqual(sut.uiState.accountStatuses[broken.id]?.level, .disconnected)
        XCTAssertEqual(sut.uiState.accountStatuses[pending.id]?.level, .needsAttention)
    }

    func testAccountsListReloadsStatusesOnChange() async throws {
        let account = try await saveAccount("Team")
        let sut = AccountsListViewModel(providerType: .apple, storage: storage, keychain: keychain, analytics: analytics, statusProvider: provider)
        await sut.loadAccounts()
        XCTAssertTrue(sut.uiState.accountStatuses.isEmpty)

        provider.statusesById = [account.id: .of(.signInExpired)]
        provider.sendChange()

        await waitUntil { sut.uiState.accountStatuses[account.id]?.level == .disconnected }

        provider.statusesById = [:]
        provider.sendChange()

        await waitUntil { sut.uiState.accountStatuses.isEmpty }
    }

    // MARK: - Settings accounts

    func testSettingsAccountsPublishesStatusesOfEveryProvider() async throws {
        let apple = try await saveAccount("Apple")
        let play = try await saveAccount("Play", provider: .googlePlay)
        provider.statusesById = [apple.id: .of(.pendingAgreements), play.id: .of(.missingCredentials)]
        let sut = SettingsAccountsViewModel(
            storage: storage, keychain: keychain, analytics: analytics, featureFlags: .googlePlayOn, statusProvider: provider
        )

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.accountStatuses[apple.id]?.level, .needsAttention)
        XCTAssertEqual(sut.uiState.accountStatuses[play.id]?.level, .disconnected)

        provider.statusesById = [:]
        provider.sendChange()
        await waitUntil { sut.uiState.accountStatuses.isEmpty }
    }

    // MARK: - Sidebar

    func testSidebarPublishesStatusesAndRefreshesOnChange() async throws {
        let account = try await saveAccount("Team")
        let sut = RootSidebarViewModel(
            storage: storage,
            reloadTrigger: Empty<Void, Never>().eraseToAnyPublisher(),
            queueCounter: { _ in 0 },
            analytics: analytics,
            statusProvider: provider
        )
        await sut.load()
        XCTAssertTrue(sut.uiState.accountStatuses.isEmpty)

        provider.statusesById = [account.id: .of(.signInExpired)]
        provider.sendChange()

        await waitUntil { sut.uiState.accountStatuses[account.id]?.level == .disconnected }
    }

    // MARK: - App Store Connect apps

    func testAppListShowsTheAccountStatusAfterLoading() async throws {
        let account = try await saveAccount("Team")
        provider.statusesById = [account.id: .of(.pendingAgreements)]
        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain, analytics: analytics, statusProvider: provider)

        await sut.loadApps()

        XCTAssertEqual(sut.uiState.accountStatus?.level, .needsAttention)
        XCTAssertEqual(sut.uiState.accountStatus?.issues, [.pendingAgreements])
        XCTAssertTrue(provider.statusRequests.allSatisfy { $0 == account.id })
    }

    func testAppListClearsTheStatusOnChangeAndRefresh() async throws {
        let account = try await saveAccount("Team")
        provider.statusesById = [account.id: .of(.signInExpired)]
        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain, analytics: analytics, statusProvider: provider)
        await sut.loadApps()
        XCTAssertEqual(sut.uiState.accountStatus?.level, .disconnected)

        provider.statusesById = [:]
        provider.sendChange()
        await waitUntil { sut.uiState.accountStatus == nil }

        provider.statusesById = [account.id: .of(.pendingAgreements)]
        await sut.refresh()
        XCTAssertEqual(sut.uiState.accountStatus?.level, .needsAttention)
    }

    func testAppListWithoutIssueHasNoStatus() async throws {
        let account = try await saveAccount("Team")
        let sut = AppListViewModel(account: account, storage: storage, keychain: keychain, analytics: analytics, statusProvider: provider)

        await sut.loadApps()

        XCTAssertNil(sut.uiState.accountStatus)
    }

    // MARK: - Google Play apps

    func testGooglePlayAppListShowsAndUpdatesTheAccountStatus() async throws {
        let account = AccountModel(name: "Play", providerType: .googlePlay)
        provider.statusesById = [account.id: .of(.signInExpired)]
        let sut = GooglePlayAppListViewModel(
            account: account,
            keychain: keychain,
            storage: storage,
            connectivity: MockConnectivityProviding(online: true),
            analytics: analytics,
            statusProvider: provider
        )

        await sut.load()
        XCTAssertEqual(sut.uiState.accountStatus?.level, .disconnected)

        provider.statusesById = [:]
        provider.sendChange()
        XCTAssertNil(sut.uiState.accountStatus)
    }

    // MARK: - Firebase

    func testFirebaseProjectListShowsAndUpdatesTheAccountStatus() async {
        let account = AccountModel(name: "Firebase", providerType: .firebase)
        provider.statusesById = [account.id: .of(.missingCredentials)]
        let sut = FirebaseProjectListViewModel(account: account, keychain: keychain, analytics: analytics, statusProvider: provider)

        await sut.load()
        XCTAssertEqual(sut.uiState.accountStatus?.issues, [.missingCredentials])

        provider.statusesById = [:]
        provider.sendChange()
        XCTAssertNil(sut.uiState.accountStatus)
    }

    func testFirebaseAppListShowsTheAccountStatus() async {
        let account = AccountModel(name: "Firebase", providerType: .firebase)
        provider.statusesById = [account.id: .of(.signInExpired)]
        let sut = FirebaseAppListViewModel(
            account: account,
            project: FirebaseProjectModel(id: "p", displayName: "Project", projectId: "p"),
            keychain: keychain,
            analytics: analytics,
            statusProvider: provider
        )

        await sut.load()

        XCTAssertEqual(sut.uiState.accountStatus?.level, .disconnected)
    }

    // MARK: - Mixed rows (Home In Review / Awaiting Release)

    func testInReviewWidgetKeysStatusesByTheRowsAccounts() async throws {
        let ok = try await saveAccount("OK")
        let broken = try await saveAccount("Broken")
        let widget = InReviewWidget(
            configuration: .init(kind: .inReview),
            storage: storage,
            statusResolver: FixedAccountStatusResolver(statuses: [broken.id: .of(.signInExpired)])
        )

        await widget.load()

        XCTAssertNil(widget.accountStatuses[ok.id])
        XCTAssertEqual(widget.accountStatuses[broken.id]?.level, .disconnected)
    }

    func testAwaitingReleaseWidgetKeysStatusesByTheRowsAccounts() async throws {
        let pending = try await saveAccount("Pending")
        let widget = AwaitingReleaseWidget(
            configuration: .init(kind: .awaitingRelease),
            storage: storage,
            statusResolver: FixedAccountStatusResolver(statuses: [pending.id: .of(.pendingAgreements)])
        )

        await widget.load()

        XCTAssertEqual(widget.accountStatuses[pending.id]?.level, .needsAttention)
    }
}

/// `AccountStatusResolving` answering fixed statuses for the given accounts.
@MainActor
private struct FixedAccountStatusResolver: AccountStatusResolving {
    let statuses: [String: AccountStatus]

    func statuses(for accounts: [AccountModel]) -> [String: AccountStatus] {
        statuses.filter { id, _ in accounts.contains { $0.id == id } }
    }
}
