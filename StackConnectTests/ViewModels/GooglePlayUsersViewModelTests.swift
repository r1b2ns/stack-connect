import XCTest
import StackCoreRust
@testable import StackConnect

@MainActor
final class GooglePlayUsersViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayUsersConnection!

    private let selfEmail = GooglePlayTestFixtures.clientEmail
    private let developerId = "4829103756618820931"

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayUsersConnection(users: Self.seedUsers)
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    static let seedUsers: [GooglePlayUserModel] = [
        GooglePlayUserModel(email: "dana@x.example", developerAccountPermissions: [GooglePlayPermissionCatalog.adminPermission]),
        GooglePlayUserModel(email: "support@x.example", grants: [
            GooglePlayGrantModel(packageName: "com.x.one", appLevelPermissions: ["CAN_VIEW_NON_FINANCIAL_DATA", "CAN_REPLY_TO_REVIEWS"])
        ]),
        GooglePlayUserModel(email: "kai@x.example", accessState: .invited, grants: [
            GooglePlayGrantModel(packageName: "com.x.one", appLevelPermissions: ["CAN_REPLY_TO_REVIEWS"])
        ]),
        GooglePlayUserModel(email: "joana@x.example", accessState: .invitationExpired,
                            expirationTime: Date(timeIntervalSinceNow: 86_400 * 30),
                            developerAccountPermissions: [], grants: [
                                GooglePlayGrantModel(packageName: "com.x.two", appLevelPermissions: ["CAN_MANAGE_TRACK_APKS"])
                            ]),
        GooglePlayUserModel(email: "lena@x.example", accessState: .accessExpired, developerAccountPermissions: ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL"]),
        GooglePlayUserModel(email: GooglePlayTestFixtures.clientEmail, developerAccountPermissions: [GooglePlayPermissionCatalog.adminPermission])
    ]

    private func makeAccount(developerId: String? = "4829103756618820931", rules: AccountRules = .allPermissions,
                             origin: AccountOrigin = .created, appsBundles: [String]? = nil) -> AccountModel {
        AccountModel(id: "play.account", name: "Play", providerType: .googlePlay, rules: rules, origin: origin,
                     appsBundles: appsBundles, googlePlayDeveloperId: developerId)
    }

    private func makeSUT(_ account: AccountModel? = nil) async throws -> GooglePlayUsersViewModel {
        let account = account ?? makeAccount()
        try await storage.save(account, id: account.id)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
                           forKey: "credentials.\(account.id)")
        return GooglePlayUsersViewModel(account: account, keychain: keychain, storage: storage,
                                        connectionFactory: connection.factory, analytics: MockAnalyticsTracker())
    }

    private func cachedUsers(accountId: String = "play.account") async throws -> [GooglePlayUserModel]? {
        try await storage.fetch(GooglePlayUsersCache.self, id: GooglePlayUsersCache.cacheKey(accountId: accountId))?.users
    }

    // MARK: - Setup state (plan U3)

    func testWithoutDeveloperIdShowsTheSetupStateAndRequestsNothing() async throws {
        let sut = try await makeSUT(makeAccount(developerId: nil))

        await sut.load()

        XCTAssertTrue(sut.uiState.showsSetup)
        XCTAssertTrue(connection.calls.isEmpty)
    }

    func testSavingTheDeveloperIdStoresItAndLoads() async throws {
        let sut = try await makeSUT(makeAccount(developerId: nil))
        await sut.load()

        sut.uiState.developerIdInput = "https://play.google.com/console/u/0/developers/123/app-list"
        await sut.saveDeveloperId()

        XCTAssertFalse(sut.uiState.showsSetup)
        XCTAssertEqual(connection.calls.first, .fetch(developerId: "123"))
        let stored = try await storage.fetch(AccountModel.self, id: "play.account")
        XCTAssertEqual(stored?.googlePlayDeveloperId, "123")
        XCTAssertEqual(sut.uiState.users.count, Self.seedUsers.count)
    }

    func testAnInvalidDeveloperIdIsRefused() async throws {
        let sut = try await makeSUT(makeAccount(developerId: nil))

        sut.uiState.developerIdInput = "northwind"
        await sut.saveDeveloperId()

        XCTAssertNotNil(sut.uiState.developerIdError)
        XCTAssertTrue(connection.calls.isEmpty)
    }

    func testTheDeveloperIdSetElsewhereIsPickedUpOnLoad() async throws {
        let sut = try await makeSUT(makeAccount(developerId: nil))
        try await storage.save(makeAccount(developerId: "777"), id: "play.account")

        await sut.load()

        XCTAssertEqual(connection.calls, [.fetch(developerId: "777")])
    }

    func testAWrongDeveloperIdOffersToChangeIt() async throws {
        let sut = try await makeSUT()
        connection.failNext(.fetch, with: StackError.Http(status: 404, message: "not found"))

        await sut.load()

        XCTAssertTrue(sut.uiState.developerIdRejected)
        XCTAssertNotNil(sut.uiState.error)
    }

    // MARK: - Offline-first

    func testShowsTheCacheThenTheFetchedUsersAndSavesThem() async throws {
        let sut = try await makeSUT()
        let cached = GooglePlayUsersCache(accountId: "play.account", users: [GooglePlayUserModel(email: "old@x.example")], fetchedAt: Date())
        try await storage.save(cached, id: cached.cacheKey)

        await sut.load()

        XCTAssertEqual(sut.uiState.users.count, Self.seedUsers.count)
        let saved = try await cachedUsers()
        XCTAssertEqual(saved?.count, Self.seedUsers.count)
    }

    func testOfflineKeepsTheCachedUsersWithoutAnError() async throws {
        let sut = try await makeSUT()
        let cached = GooglePlayUsersCache(accountId: "play.account", users: [GooglePlayUserModel(email: "old@x.example")], fetchedAt: Date())
        try await storage.save(cached, id: cached.cacheKey)
        connection.failNext(.fetch, with: OfflineError.noConnection)

        await sut.load()

        XCTAssertEqual(sut.uiState.users.map(\.email), ["old@x.example"])
        XCTAssertNil(sut.uiState.error)
    }

    func testWithoutTheUsersRuleNothingIsRequested() async throws {
        let sut = try await makeSUT(makeAccount(rules: AccountRules(apps: [.view]), origin: .imported))

        await sut.load()

        XCTAssertTrue(connection.calls.isEmpty)
    }

    func testTheServiceAccountIsKnownForSelfProtection() async throws {
        let sut = try await makeSUT()

        XCTAssertEqual(sut.uiState.serviceAccountEmail, selfEmail)
    }

    func testSortsPeopleThenInvitationsThenExpiredThenServiceAccounts() {
        let sorted = GooglePlayUsersViewModel.sorted(Self.seedUsers.shuffled())

        XCTAssertEqual(sorted.map(\.email), [
            "dana@x.example", "support@x.example", "kai@x.example", "joana@x.example", "lena@x.example", selfEmail
        ])
    }
}
