import XCTest
import StackProtocols
@testable import StackConnect

/// Settings › Accounts › an account: status and "Sign in again", Export (off
/// with why) and Delete.
@MainActor
final class SettingsAccountDetailViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var statuses: MockAccountStatusProvider!

    private let password = "aVeryStrongPass123"

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

    private func makeSUT(_ account: AccountModel) -> SettingsAccountDetailViewModel {
        SettingsAccountDetailViewModel(
            account: account,
            storage: storage,
            keychain: keychain,
            analytics: analytics,
            statusProvider: statuses,
            notificationCenter: NotificationCenter()
        )
    }

    private func makeAppleAccount() -> AccountModel {
        let account = AccountModel(name: "Team", providerType: .apple)
        keychain.setObject(AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "pk"), forKey: "credentials.\(account.id)")
        return account
    }

    private func makeGooglePlayAccount(json: String = GooglePlayTestFixtures.serviceAccountJSON()) -> AccountModel {
        let account = AccountModel(name: "Play", providerType: .googlePlay)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: "credentials.\(account.id)")
        return account
    }

    private func decryptPayload(at url: URL) throws -> [String: Any] {
        let json = try AccountCrypto.decrypt(data: try Data(contentsOf: url), password: password)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(json.data(using: .utf8))) as? [String: Any])
    }

    // MARK: - Status and reconnect

    func testAConnectedAccountHasNoStatusNorReconnect() {
        let sut = makeSUT(makeAppleAccount())

        XCTAssertNil(sut.uiState.status)
        XCTAssertNil(sut.uiState.reconnectMethod)
    }

    func testAnExpiredAppleIdSessionOffersSignInAgain() {
        let account = AccountModel(name: "Personal", providerType: .apple, authMethod: .appleIdSignIn)
        keychain.setObject(
            AppleCredentials(webSession: AppleWebSessionReference(appleId: "dev@example.com", teamId: 1, teamName: "Acme")),
            forKey: "credentials.\(account.id)"
        )
        statuses.statusesById = [account.id: .of(.signInExpired)]

        let sut = makeSUT(account)

        XCTAssertEqual(sut.uiState.status?.level, .disconnected)
        XCTAssertEqual(sut.uiState.reconnectMethod, .appleIdSignIn)
    }

    func testAnExpiredGoogleLoginOffersSignInAgain() {
        let account = AccountModel(name: "Client", providerType: .googlePlay, authMethod: .googleSignIn)
        keychain.setObject(GooglePlayCredentials(googleLoginId: "user-1"), forKey: "credentials.\(account.id)")
        statuses.statusesById = [account.id: .of(.signInExpired)]

        XCTAssertEqual(makeSUT(account).uiState.reconnectMethod, .googleSignIn)
    }

    func testASignInWhoseSessionIsGoneCantBeReconnectedHere() {
        let account = AccountModel(name: "Personal", providerType: .apple, authMethod: .appleIdSignIn)
        statuses.statusesById = [account.id: .of(.signInExpired, .missingCredentials)]

        XCTAssertNil(makeSUT(account).uiState.reconnectMethod)
    }

    func testAnExpiredSharedAccountOffersReimport() {
        let account = AccountModel(name: "Shared", providerType: .apple, origin: .imported, expirationDate: .distantPast)
        statuses.statusesById = [account.id: .of(.accessExpired)]

        XCTAssertEqual(makeSUT(account).uiState.reconnectMethod, .scexportFile)
    }

    func testAKeyFileWithPendingAgreementsHasNoReconnect() {
        let account = makeAppleAccount()
        statuses.statusesById = [account.id: .of(.pendingAgreements)]

        XCTAssertNil(makeSUT(account).uiState.reconnectMethod)
    }

    func testLoadPicksUpEditsAndStatusChanges() async throws {
        let account = makeAppleAccount()
        let sut = makeSUT(account)
        try await storage.save(account.updating(name: "Renamed"), id: account.id)
        statuses.statusesById = [account.id: .of(.pendingAgreements)]

        await sut.load()

        XCTAssertEqual(sut.uiState.account.name, "Renamed")
        XCTAssertEqual(sut.uiState.status?.level, .needsAttention)
    }

    // MARK: - Export

    func testExportReasons() {
        let session = AccountModel(name: "S", providerType: .apple, authMethod: .appleIdSignIn)
        let google = AccountModel(name: "G", providerType: .firebase, authMethod: .googleSignIn)
        let imported = AccountModel(name: "I", providerType: .apple, origin: .imported)
        let firebase = AccountModel(name: "F", providerType: .firebase)

        XCTAssertNil(SettingsAccountDetailUiState.exportUnavailableReason(for: makeAppleAccount()))
        XCTAssertEqual(SettingsAccountDetailUiState.exportUnavailableReason(for: session), session.exportUnavailableReason)
        XCTAssertNotNil(SettingsAccountDetailUiState.exportUnavailableReason(for: google))
        XCTAssertNotNil(SettingsAccountDetailUiState.exportUnavailableReason(for: imported))
        XCTAssertNotNil(SettingsAccountDetailUiState.exportUnavailableReason(for: firebase))
    }

    func testExportWritesAppsBundlesWhenNonEmpty() throws {
        let sut = makeSUT(makeAppleAccount())

        let url = try XCTUnwrap(sut.exportAccountWithRules(exportName: "Team", rules: .allPermissions, password: password, expirationDate: nil, appsBundles: ["com.a", "com.b"]))

        let bundles = try XCTUnwrap(try decryptPayload(at: url)["appsBundles"] as? [String])
        XCTAssertEqual(Set(bundles), ["com.a", "com.b"])
    }

    func testExportOmitsAppsBundlesWhenNilOrEmpty() throws {
        let sut = makeSUT(makeAppleAccount())

        for scope in [nil, [String]()] {
            let url = try XCTUnwrap(sut.exportAccountWithRules(exportName: "Team", rules: .allPermissions, password: password, expirationDate: nil, appsBundles: scope))
            XCTAssertNil(try decryptPayload(at: url)["appsBundles"])
        }
    }

    func testExportGooglePlayAccountWritesTheServiceAccountJSON() throws {
        let json = GooglePlayTestFixtures.serviceAccountJSON()
        let sut = makeSUT(makeGooglePlayAccount(json: json))

        let url = try XCTUnwrap(sut.exportAccountWithRules(exportName: "Play Team", rules: AccountRules(apps: [.view]), password: password, expirationDate: nil, appsBundles: ["com.example.one"]))

        let dict = try decryptPayload(at: url)
        XCTAssertEqual(dict["credentials"] as? [String: String], ["serviceAccountJSON": json])
        XCTAssertEqual(dict["appsBundles"] as? [String], ["com.example.one"])
    }

    func testExportFirebaseAccountProducesNoFile() {
        let account = AccountModel(name: "Firebase", providerType: .firebase)
        keychain.setObject(FirebaseCredentials(serviceAccountJSON: "{}"), forKey: "credentials.\(account.id)")

        XCTAssertNil(makeSUT(account).exportAccountWithRules(exportName: "Firebase", rules: .allPermissions, password: password, expirationDate: nil, appsBundles: nil))
    }

    func testExportTracksSuccessWithShapeOnly() {
        let sut = makeSUT(makeAppleAccount())

        _ = sut.exportAccountWithRules(exportName: "Team", rules: .allPermissions, password: password, expirationDate: .now, appsBundles: ["com.a"])

        XCTAssertEqual(analytics.actions(of: .exportAccount), [
            .action(.exportAccount, on: .exportAccount, result: .success, parameters: [
                AnalyticsParameterKey.hasExpiration: .bool(true),
                AnalyticsParameterKey.scoped: .bool(true)
            ])
        ])
    }

    func testAppsForExportOfAGooglePlayAccountReadsItsCachedAppList() async throws {
        let account = makeGooglePlayAccount()
        try await storage.save(
            [GooglePlayAppItem(id: "com.example.one", packageName: "com.example.one", title: "One", isManuallyAdded: false)],
            id: GooglePlayAppItem.cacheKey(accountId: account.id)
        )

        let apps = await makeSUT(account).appsForExport()

        XCTAssertEqual(apps.map(\.bundleId), ["com.example.one"])
        XCTAssertEqual(apps.map(\.name), ["One"])
    }

    // MARK: - Delete

    func testDeleteAccountRemovesItsTemplatesAndCredentials() async throws {
        let deleted = makeAppleAccount()
        let kept = makeAppleAccount()
        try await storage.save(deleted, id: deleted.id)
        try await storage.save(kept, id: kept.id)
        try await storage.save(ReplyTemplateModel(id: "deleted", accountId: deleted.id, title: "T", body: "B"), id: "deleted")
        try await storage.save(ReplyTemplateModel(id: "kept", accountId: kept.id, title: "T", body: "B"), id: "kept")

        let isGone = await makeSUT(deleted).deleteAccount()

        XCTAssertTrue(isGone)
        let templates = try await storage.fetchAll(ReplyTemplateModel.self)
        XCTAssertEqual(templates.map(\.id), ["kept"])
        let credentials: AppleCredentials? = keychain.object(forKey: "credentials.\(deleted.id)")
        XCTAssertNil(credentials)
    }

    func testDeleteGooglePlayAccountRemovesItsCachedApps() async throws {
        let account = makeGooglePlayAccount()
        try await storage.save(account, id: account.id)
        let cacheKey = GooglePlayAppItem.cacheKey(accountId: account.id)
        try await storage.save([GooglePlayAppItem(id: "com.a", packageName: "com.a", title: nil, isManuallyAdded: true)], id: cacheKey)

        _ = await makeSUT(account).deleteAccount()

        let cached = try await storage.fetch([GooglePlayAppItem].self, id: cacheKey)
        XCTAssertNil(cached)
        XCTAssertNil(keychain.data(forKey: "credentials.\(account.id)"))
    }

    func testDeleteTracksConfirmTapAndResult() async throws {
        let account = makeAppleAccount()
        try await storage.save(account, id: account.id)

        _ = await makeSUT(account).deleteAccount()

        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .accountDetail)])
        XCTAssertEqual(analytics.results(of: .deleteAccount), [.success])
    }

    func testAFailedDeleteKeepsTheScreen() async throws {
        let account = makeAppleAccount()
        try await storage.save(account, id: account.id)
        await storage.failDelete(AccountModel.self, id: account.id)

        let isGone = await makeSUT(account).deleteAccount()

        XCTAssertFalse(isGone)
        XCTAssertEqual(analytics.results(of: .deleteAccount), [.failure])
    }
}
