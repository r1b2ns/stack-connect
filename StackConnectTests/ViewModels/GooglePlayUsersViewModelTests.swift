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

    func testARefusedDeveloperIdSaysWhyAndReportsTheInput() async throws {
        let sut = try await makeSUT(makeAccount(developerId: nil))

        sut.uiState.developerIdInput = "https://play.google.com/console/u/0/developers/app-list"
        await sut.saveDeveloperId()

        XCTAssertEqual(sut.uiState.developerIdError, GooglePlayDeveloperId.invalidMessage)
        XCTAssertEqual(
            sut.uiState.developerIdErrorDetails.first,
            String(localized: "Developer ID (as entered): \("\"https://play.google.com/console/u/0/developers/app-list\"")")
        )
        XCTAssertTrue(sut.uiState.showsSetup)
    }

    func testAPastedPlayConsoleURLIsSaved() async throws {
        let sut = try await makeSUT(makeAccount(developerId: nil))

        sut.uiState.developerIdInput = "https://play.google.com/console/u/0/developers/\(developerId)/app-list?hl=en"
        await sut.saveDeveloperId()

        XCTAssertNil(sut.uiState.developerIdError)
        XCTAssertEqual(connection.calls.first, .fetch(developerId: developerId))
    }

    func testALoadFailureCarriesTechnicalDetailsForTheReport() async throws {
        let sut = try await makeSUT()
        let googleMessage = "Google Play found no developer account with ID \(developerId) (HTTP 404): check the developer ID. Google said: Not found. [NOT_FOUND]"
        connection.failNext(.fetch, with: StackError.Http(status: 404, message: googleMessage))

        await sut.load()

        XCTAssertEqual(sut.uiState.error?.components(separatedBy: "\n").last, googleMessage, "Google's message is shown")
        let details = sut.uiState.errorDetails
        XCTAssertTrue(details.contains(String(localized: "Operation: \("developers.users.list")")))
        XCTAssertTrue(details.contains(String(localized: "HTTP status: \(404)")))
        XCTAssertTrue(details.contains(String(localized: "Message: \(googleMessage)")))
        XCTAssertTrue(details.contains(String(localized: "Developer ID (as stored): \("\"\(developerId)\"")")))
        XCTAssertTrue(details.contains(String(localized: "Resource: \("developers/\(developerId)/users")")))
        XCTAssertTrue(details.contains(String(localized: "Service account: \(selfEmail)")))

        connection.failNext(.fetch, with: StackError.Network(message: "x"))
        await sut.refresh()
        XCTAssertFalse(sut.uiState.errorDetails.contains(String(localized: "HTTP status: \(404)")), "A new load replaces the details")
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

    // MARK: - Filters and search (plan U4)

    func testFiltersAndSearch() async throws {
        let sut = try await makeSUT()
        await sut.load()

        sut.uiState.selectedFilter = .admins
        XCTAssertEqual(Set(sut.uiState.filteredUsers.map(\.email)), ["dana@x.example", selfEmail])
        sut.uiState.selectedFilter = .invited
        XCTAssertEqual(sut.uiState.filteredUsers.map(\.email), ["kai@x.example"])
        sut.uiState.selectedFilter = .expired
        XCTAssertEqual(sut.uiState.filteredUsers.map(\.email), ["joana@x.example", "lena@x.example"])
        sut.uiState.selectedFilter = .serviceAccounts
        XCTAssertEqual(sut.uiState.filteredUsers.map(\.email), [selfEmail])

        sut.uiState.selectedFilter = .all
        sut.uiState.searchQuery = "SUPP"
        XCTAssertEqual(sut.uiState.filteredUsers.map(\.email), ["support@x.example"])
    }

    // MARK: - Remove

    func testRemoveAsksForConfirmationThenDeletesAndUpdatesTheCache() async throws {
        let sut = try await makeSUT()
        await sut.load()
        let support = try XCTUnwrap(sut.uiState.users.first { $0.email == "support@x.example" })

        sut.requestRemove(support)
        XCTAssertEqual(sut.uiState.confirmRemove, support)
        await sut.remove(support)

        XCTAssertTrue(connection.calls.contains(.delete(email: "support@x.example")))
        XCTAssertFalse(sut.uiState.users.contains(support))
        let cached = try await cachedUsers()
        XCTAssertEqual(cached?.contains(support), false)
        XCTAssertNotNil(sut.uiState.toastMessage)
    }

    func testAFailedRemoveLeavesTheListAndTheCacheUntouched() async throws {
        let sut = try await makeSUT()
        await sut.load()
        let support = try XCTUnwrap(sut.uiState.users.first { $0.email == "support@x.example" })
        connection.failNext(.delete, with: StackError.Http(status: 500, message: ""))

        await sut.remove(support)

        XCTAssertTrue(sut.uiState.users.contains(support))
        let cached = try await cachedUsers()
        XCTAssertEqual(cached?.count, Self.seedUsers.count)
        XCTAssertNotNil(sut.uiState.actionError)
    }

    func testTheServiceAccountItselfCantBeRemoved() async throws {
        let sut = try await makeSUT()
        await sut.load()
        let me = try XCTUnwrap(sut.uiState.users.first { $0.email == selfEmail })

        sut.requestRemove(me)
        await sut.remove(me)

        XCTAssertNil(sut.uiState.confirmRemove)
        XCTAssertEqual(sut.uiState.refusalMessage, GooglePlayUsersAccess.message(for: .selfProtected))
        XCTAssertFalse(connection.calls.contains(.delete(email: selfEmail)))
    }

    func testRemoveNeedsTheDeleteRule() async throws {
        let sut = try await makeSUT(makeAccount(rules: AccountRules(users: [.view, .edit]), origin: .imported))
        await sut.load()
        let support = try XCTUnwrap(sut.uiState.users.first { $0.email == "support@x.example" })

        sut.requestRemove(support)
        await sut.remove(support)

        XCTAssertEqual(sut.uiState.refusalMessage, GooglePlayUsersAccess.message(for: .notPermitted))
        XCTAssertFalse(connection.calls.contains(.delete(email: "support@x.example")))
    }

    func testAScopedAccountCantRemoveSomeoneWithAccessOutsideItsApps() async throws {
        let sut = try await makeSUT(makeAccount(origin: .imported, appsBundles: ["com.x.one"]))
        await sut.load()
        let lena = try XCTUnwrap(sut.uiState.users.first { $0.email == "lena@x.example" })
        let support = try XCTUnwrap(sut.uiState.users.first { $0.email == "support@x.example" })

        sut.requestRemove(lena)
        XCTAssertEqual(sut.uiState.refusalMessage, GooglePlayUsersAccess.message(for: .outsideScope))
        sut.requestRemove(support)
        XCTAssertEqual(sut.uiState.confirmRemove, support, "Only in-scope apps: allowed")
    }

    // MARK: - Resend (plan U8)

    func testResendIsDeletePlusInviteWithTheSamePermissions() async throws {
        let sut = try await makeSUT()
        await sut.load()
        let joana = try XCTUnwrap(sut.uiState.users.first { $0.email == "joana@x.example" })

        sut.requestResend(joana)
        XCTAssertEqual(sut.uiState.confirmResend, joana)
        await sut.resend(joana)

        let writes = connection.calls.filter { if case .fetch = $0 { return false } else { return true } }
        XCTAssertEqual(writes, [
            .delete(email: "joana@x.example"),
            .invite(email: "joana@x.example", accountPermissions: [], grants: joana.grants, expiration: joana.expirationTime)
        ])
        XCTAssertEqual(sut.uiState.users.first { $0.email == "joana@x.example" }?.accessState, .invited)
        let cached = try await cachedUsers()
        XCTAssertEqual(cached?.first { $0.email == "joana@x.example" }?.accessState, .invited)
    }

    func testResendIsOnlyForExpiredInvitations() async throws {
        let sut = try await makeSUT()
        await sut.load()
        let kai = try XCTUnwrap(sut.uiState.users.first { $0.email == "kai@x.example" })

        sut.requestResend(kai)
        await sut.resend(kai)

        XCTAssertNil(sut.uiState.confirmResend)
        XCTAssertNotNil(sut.uiState.refusalMessage)
        XCTAssertFalse(connection.calls.contains(.delete(email: "kai@x.example")))
    }

    func testAResendWhoseInviteFailsDropsTheRemovedInvitation() async throws {
        let sut = try await makeSUT()
        await sut.load()
        let joana = try XCTUnwrap(sut.uiState.users.first { $0.email == "joana@x.example" })
        connection.failNext(.invite, with: StackError.Http(status: 400, message: "not a Google account"))

        await sut.resend(joana)

        XCTAssertFalse(sut.uiState.users.contains { $0.email == "joana@x.example" })
        XCTAssertNotNil(sut.uiState.actionError)
        XCTAssertTrue(sut.uiState.actionErrorDetails.contains(String(localized: "Operation: \("developers.users.create")")))
    }

    // MARK: - Invite (plan U6)

    private func inviteForm(_ email: String, preset: GooglePlayPermissionPreset = .support,
                            grant: String? = nil) -> GooglePlayInviteForm {
        var form = GooglePlayInviteForm()
        form.email = email
        form.apply(preset)
        if let grant { form.setGrant(packageName: grant, values: ["CAN_REPLY_TO_REVIEWS"]) }
        return form
    }

    func testInviteSendsAndShowsThePendingUser() async throws {
        let sut = try await makeSUT()
        await sut.load()
        var form = inviteForm("new@x.example", grant: "com.x.one")
        form.expiration = Date(timeIntervalSinceNow: 86_400 * 60)

        let error = await sut.invite(form)

        XCTAssertNil(error)
        XCTAssertEqual(connection.calls.last, .invite(email: "new@x.example",
                                                       accountPermissions: ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_REPLY_TO_REVIEWS_GLOBAL"],
                                                       grants: form.grants, expiration: form.expiration))
        let invited = try XCTUnwrap(sut.uiState.users.first { $0.email == "new@x.example" })
        XCTAssertEqual(invited.accessState, .invited)
        let cached = try await cachedUsers()
        XCTAssertEqual(cached?.contains(invited), true)
        XCTAssertNotNil(sut.uiState.toastMessage)
    }

    func testInviteRefusesAnExistingUserWithoutARequest() async throws {
        let sut = try await makeSUT()
        await sut.load()

        let error = await sut.invite(inviteForm("SUPPORT@x.example"))

        XCTAssertNotNil(error)
        XCTAssertFalse(connection.calls.contains { if case .invite = $0 { return true } else { return false } })
    }

    func testAFailedInviteReturnsTheTranslatedErrorAndChangesNothing() async throws {
        let sut = try await makeSUT()
        await sut.load()
        connection.failNext(.invite, with: StackError.Http(status: 400, message: "Not a valid Google account"))

        let error = await sut.invite(inviteForm("new@x.example"))

        XCTAssertEqual(error, String(localized: "Google Play can only invite Google accounts. Check the address, or ask the person which Google account (Gmail or Google Workspace) to use."))
        XCTAssertTrue(sut.uiState.inviteErrorDetails.contains(String(localized: "Message: \("Not a valid Google account")")))
        XCTAssertTrue(sut.uiState.inviteErrorDetails.contains(String(localized: "Resource: \("developers/\(developerId)/users")")))
        XCTAssertFalse(sut.uiState.users.contains { $0.email == "new@x.example" })
        let cached = try await cachedUsers()
        XCTAssertEqual(cached?.count, Self.seedUsers.count)
    }

    func testAScopedAccountInvitesOnlyToItsAppsWithoutAccountPermissions() async throws {
        let sut = try await makeSUT(makeAccount(origin: .imported, appsBundles: ["com.x.one"]))
        await sut.load()

        let accountWide = await sut.invite(inviteForm("a@x.example"))
        XCTAssertEqual(accountWide, GooglePlayUsersAccess.message(for: .outsideScope))
        let outside = await sut.invite(inviteForm("b@x.example", preset: .custom, grant: "com.x.two"))
        XCTAssertEqual(outside, GooglePlayUsersAccess.message(for: .outsideScope))
        let inside = await sut.invite(inviteForm("c@x.example", preset: .custom, grant: "com.x.one"))
        XCTAssertNil(inside)
    }

    func testInviteNeedsTheAddRule() async throws {
        let sut = try await makeSUT(makeAccount(rules: AccountRules(users: [.view, .edit, .delete]), origin: .imported))
        await sut.load()

        XCTAssertFalse(sut.uiState.canShowInvite)
        let error = await sut.invite(inviteForm("a@x.example"))
        XCTAssertEqual(error, GooglePlayUsersAccess.message(for: .notPermitted))
    }
}
