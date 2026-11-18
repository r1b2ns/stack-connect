import XCTest
import StackCoreRust
@testable import StackConnect

@MainActor
final class GooglePlayUserDetailViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var connection: MockGooglePlayUsersConnection!

    private let admin = GooglePlayPermissionCatalog.adminPermission
    private let support = GooglePlayUserModel(email: "support@x.example", grants: [
        GooglePlayGrantModel(packageName: "com.x.one", appLevelPermissions: ["CAN_VIEW_NON_FINANCIAL_DATA", "CAN_REPLY_TO_REVIEWS"])
    ])
    private var me: GooglePlayUserModel {
        GooglePlayUserModel(email: GooglePlayTestFixtures.clientEmail, developerAccountPermissions: [admin])
    }

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        connection = MockGooglePlayUsersConnection(users: [support, me])
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        connection = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeAccount(rules: AccountRules = .allPermissions, appsBundles: [String]? = nil) -> AccountModel {
        AccountModel(id: "play.account", name: "Play", providerType: .googlePlay, rules: rules,
                     origin: appsBundles == nil && rules == .allPermissions ? .created : .imported,
                     appsBundles: appsBundles, googlePlayDeveloperId: "123")
    }

    private func makeSUT(_ user: GooglePlayUserModel, account: AccountModel? = nil) async throws -> GooglePlayUserDetailViewModel {
        let account = account ?? makeAccount()
        try await storage.save(account, id: account.id)
        try await storage.save(GooglePlayUsersCache(accountId: account.id, users: [support, me], fetchedAt: Date()),
                               id: GooglePlayUsersCache.cacheKey(accountId: account.id))
        try await storage.save([
            GooglePlayAppItem(id: "com.x.one", packageName: "com.x.one", title: "One", isManuallyAdded: false),
            GooglePlayAppItem(id: "com.x.two", packageName: "com.x.two", title: "Two", isManuallyAdded: false)
        ], id: GooglePlayAppItem.cacheKey(accountId: account.id))
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
                           forKey: "credentials.\(account.id)")
        let sut = GooglePlayUserDetailViewModel(user: user, account: account, keychain: keychain, storage: storage,
                                                connectionFactory: connection.factory, analytics: MockAnalyticsTracker())
        await sut.load()
        return sut
    }

    private func cachedUser(_ email: String) async throws -> GooglePlayUserModel? {
        try await storage.fetch(GooglePlayUsersCache.self, id: GooglePlayUsersCache.cacheKey(accountId: "play.account"))?
            .users.first { $0.email == email }
    }

    // MARK: - Credential-aware copy

    func testPartialAccessFooterFollowsTheAuthMethod() {
        let user = GooglePlayUserModel(email: "partial@x.example", partial: true)
        XCTAssertEqual(
            GooglePlayUserDetailUiState(account: makeAccount(), user: user, serviceAccountEmail: nil).partialAccessFooter,
            String(localized: "Google returned only part of this user's access (they also have access this service account can't see). Edit them in Play Console.")
        )
        let signIn = AccountModel(id: "play.signin", name: "Play", providerType: .googlePlay, authMethod: .googleSignIn)
        XCTAssertEqual(
            GooglePlayUserDetailUiState(account: signIn, user: user, serviceAccountEmail: nil).partialAccessFooter,
            String(localized: "Google returned only part of this user's access (they also have access the signed-in Google account can't see). Edit them in Play Console.")
        )
    }

    func testAGrantFailureOfAGoogleSignInAccountNamesTheSignedInGoogleAccount() async throws {
        let account = AccountModel(id: "play.account", name: "Play", providerType: .googlePlay,
                                   googlePlayDeveloperId: "123", authMethod: .googleSignIn)
        let sut = try await makeSUT(support, account: account)
        connection.failNext(.setGrant, with: StackError.Http(status: 403, message: ""))

        _ = await sut.saveGrant(packageName: "com.x.two", permissions: ["CAN_REPLY_TO_REVIEWS"])

        XCTAssertEqual(
            sut.uiState.errorMessage,
            String(localized: "Google Play refused access to this developer account. Check the Developer ID, and that the signed-in Google account has the “Admin (all permissions)” permission.")
        )
    }

    // MARK: - Account permissions

    func testSavesTheAccountPermissionsWithViewAppInformationAndTheExpiry() async throws {
        let sut = try await makeSUT(support)
        let reply = try XCTUnwrap(GooglePlayPermissionCatalog.all.first { $0.id == "replyToReviews" })
        let expiry = Date(timeIntervalSinceNow: 86_400 * 10)

        sut.setAccountPermission(reply, isOn: true)
        sut.uiState.draftExpiration = expiry
        XCTAssertTrue(sut.uiState.hasChanges)
        await sut.save()

        XCTAssertEqual(connection.calls.last, .update(email: "support@x.example",
                                                       accountPermissions: ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_REPLY_TO_REVIEWS_GLOBAL"],
                                                       expiration: expiry))
        XCTAssertFalse(sut.uiState.hasChanges)
        XCTAssertEqual(sut.uiState.user.grants, support.grants, "The grants survive an update")
        let cached = try await cachedUser("support@x.example")
        XCTAssertEqual(cached?.developerAccountPermissions.contains("CAN_REPLY_TO_REVIEWS_GLOBAL"), true)
    }

    func testAFailedSaveKeepsTheDraftAndTheCache() async throws {
        let sut = try await makeSUT(support)
        sut.setAdmin(true)
        connection.failNext(.update, with: StackError.Http(status: 500, message: ""))

        await sut.save()

        XCTAssertTrue(sut.uiState.hasChanges)
        XCTAssertNotNil(sut.uiState.errorMessage)
        XCTAssertTrue(sut.uiState.errorDetails.contains(String(localized: "Operation: \("developers.users.patch")")))
        XCTAssertTrue(sut.uiState.errorDetails.contains(String(localized: "Resource: \("developers/123/users/support@x.example")")))
        let cached = try await cachedUser("support@x.example")
        XCTAssertEqual(cached, support)
    }

    func testAGrantFailureWhileTheAppPermissionsSheetIsOpenShowsInTheSheet() async throws {
        let sut = try await makeSUT(support)
        sut.uiState.grantEditor = GooglePlayGrantEditorRequest(packageName: "com.x.two", permissions: [])
        connection.failNext(.setGrant, with: StackError.Http(status: 403, message: "The caller does not have permission [PERMISSION_DENIED]"))

        let saved = await sut.saveGrant(packageName: "com.x.two", permissions: ["CAN_REPLY_TO_REVIEWS"])

        XCTAssertFalse(saved)
        XCTAssertNil(sut.uiState.errorMessage, "No alert under the sheet")
        let failure = try XCTUnwrap(sut.uiState.grantEditorError)
        XCTAssertTrue(failure.message.hasSuffix("\nThe caller does not have permission [PERMISSION_DENIED]"))
        XCTAssertTrue(failure.technicalDetails.contains(String(localized: "Resource: \("developers/123/users/support@x.example/grants/com.x.two")")))
    }

    func testUnknownPermissionsAreKeptOnSave() async throws {
        var user = support
        user.developerAccountPermissions = ["CAN_SOMETHING_NEW_GLOBAL"]
        let sut = try await makeSUT(user)
        let orders = try XCTUnwrap(GooglePlayPermissionCatalog.all.first { $0.id == "orders" })

        sut.setAccountPermission(orders, isOn: true)
        await sut.save()

        guard case .update(_, let permissions, _)? = connection.calls.last else { return XCTFail("No update") }
        XCTAssertTrue(permissions.contains("CAN_SOMETHING_NEW_GLOBAL"))
        XCTAssertTrue(permissions.contains("CAN_MANAGE_ORDERS_GLOBAL"))
    }

    // MARK: - Self-protection (plan U7)

    func testTheServiceAccountKeepsItsAdmin() async throws {
        let sut = try await makeSUT(me)

        sut.setAdmin(false)

        XCTAssertTrue(sut.uiState.draftIsAdmin)
        XCTAssertEqual(sut.uiState.refusalMessage, GooglePlayUsersAccess.message(for: .selfProtected))
    }

    func testTheServiceAccountCantBeRemoved() async throws {
        let sut = try await makeSUT(me)

        sut.requestRemove()
        let removed = await sut.remove()

        XCTAssertFalse(sut.uiState.confirmRemove)
        XCTAssertFalse(removed)
        XCTAssertFalse(connection.calls.contains(.delete(email: me.email)))
    }

    func testAnotherAdminCanLoseAdmin() async throws {
        let dana = GooglePlayUserModel(email: "dana@x.example", developerAccountPermissions: [admin])
        let sut = try await makeSUT(dana)

        sut.setAdmin(false)

        XCTAssertFalse(sut.uiState.draftIsAdmin)
        XCTAssertNil(sut.uiState.refusalMessage)
    }

    // MARK: - Remove

    func testRemoveDeletesAndDropsTheUserFromTheCache() async throws {
        let sut = try await makeSUT(support)

        sut.requestRemove()
        XCTAssertTrue(sut.uiState.confirmRemove)
        let removed = await sut.remove()

        XCTAssertTrue(removed)
        let cached = try await cachedUser("support@x.example")
        XCTAssertNil(cached)
    }

    // MARK: - App access

    func testAddsAndRemovesAppAccess() async throws {
        let sut = try await makeSUT(support)
        XCTAssertEqual(sut.uiState.availableAppsForNewGrant.map(\.packageName), ["com.x.two"])

        let saved = await sut.saveGrant(packageName: "com.x.two", permissions: ["CAN_MANAGE_TRACK_APKS"])
        XCTAssertTrue(saved)
        XCTAssertEqual(connection.calls.last, .setGrant(email: "support@x.example", packageName: "com.x.two",
                                                         permissions: ["CAN_VIEW_NON_FINANCIAL_DATA", "CAN_MANAGE_TRACK_APKS"]))
        XCTAssertEqual(sut.uiState.user.grants.count, 2)

        let grant = try XCTUnwrap(sut.uiState.user.grant(for: "com.x.one"))
        sut.requestRemoveGrant(grant)
        XCTAssertEqual(sut.uiState.confirmRemoveGrant, grant)
        let removed = await sut.removeGrant(grant)
        XCTAssertTrue(removed)
        let cached = try await cachedUser("support@x.example")
        XCTAssertEqual(cached?.grants.map(\.packageName), ["com.x.two"])
    }

    func testAGrantNeedsAPermission() async throws {
        let sut = try await makeSUT(support)

        let saved = await sut.saveGrant(packageName: "com.x.two", permissions: [])

        XCTAssertFalse(saved)
        XCTAssertNotNil(sut.uiState.errorMessage)
    }

    // MARK: - Rules and scope (plan U6)

    func testAScopedAccountOnlyGrantsItsAppsAndCantChangeAccountPermissions() async throws {
        let sut = try await makeSUT(support, account: makeAccount(appsBundles: ["com.x.one"]))

        XCTAssertFalse(sut.uiState.canEditAccountPermissions)
        XCTAssertTrue(sut.uiState.availableAppsForNewGrant.isEmpty, "com.x.two is outside the scope")
        sut.setAdmin(true)
        XCTAssertEqual(sut.uiState.refusalMessage, GooglePlayUsersAccess.message(for: .outsideScope))
        let saved = await sut.saveGrant(packageName: "com.x.two", permissions: ["CAN_REPLY_TO_REVIEWS"])
        XCTAssertFalse(saved)
        let edited = await sut.saveGrant(packageName: "com.x.one", permissions: ["CAN_REPLY_TO_REVIEWS", "CAN_MANAGE_TRACK_APKS"])
        XCTAssertTrue(edited)
    }

    func testAViewOnlyImportCantEdit() async throws {
        let sut = try await makeSUT(support, account: makeAccount(rules: AccountRules(users: [.view])))

        XCTAssertFalse(sut.uiState.access.canEdit)
        let saved = await sut.saveGrant(packageName: "com.x.one", permissions: ["CAN_REPLY_TO_REVIEWS"])
        XCTAssertFalse(saved)
        XCTAssertEqual(sut.uiState.refusalMessage, GooglePlayUsersAccess.message(for: .notPermitted))
    }

    func testAPartialUserIsReadOnly() async throws {
        var partial = support
        partial.partial = true
        let sut = try await makeSUT(partial)

        XCTAssertFalse(sut.uiState.canEditAccountPermissions)
        XCTAssertFalse(sut.uiState.canAddGrant)
    }

    func testAdminsGetNoPerAppAccess() async throws {
        let dana = GooglePlayUserModel(email: "dana@x.example", developerAccountPermissions: [admin])
        let sut = try await makeSUT(dana)

        XCTAssertFalse(sut.uiState.canAddGrant, "Admin already covers every app")
    }
}
