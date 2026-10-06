import XCTest
@testable import StackConnect

@MainActor
final class SettingsAccountsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var sut: SettingsAccountsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        sut = SettingsAccountsViewModel(storage: storage, keychain: keychain)
    }

    override func tearDown() async throws {
        sut = nil
        storage = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeAppleAccount() -> AccountModel {
        let account = AccountModel(name: "Team", providerType: .apple)
        keychain.setObject(
            AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "pk"),
            forKey: "credentials.\(account.id)"
        )
        return account
    }

    /// Decrypts an exported `.scexport` URL and returns its parsed JSON dict.
    private func decryptPayload(at url: URL, password: String) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let json = try AccountCrypto.decrypt(data: data, password: password)
        let jsonData = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
    }

    /// Encrypts a plaintext payload dict into a temp `.scexport` file for import tests.
    private func makeImportFile(payload: [String: Any], password: String) throws -> URL {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        let encrypted = try AccountCrypto.encrypt(json: json, password: password)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).scexport")
        try encrypted.write(to: url)
        return url
    }

    private func appleCredentialsPayload() -> [String: String] {
        ["issuerID": "issuer", "privateKeyID": "kid", "privateKey": "pk"]
    }

    // MARK: - Delete

    func testDeleteAccountRemovesItsReplyTemplatesAndReloads() async throws {
        let deleted = makeAppleAccount()
        let kept = makeAppleAccount()
        try await storage.save(deleted, id: deleted.id)
        try await storage.save(kept, id: kept.id)
        let deletedTemplate = ReplyTemplateModel(id: "deleted", accountId: deleted.id, title: "T", body: "B")
        let keptTemplate = ReplyTemplateModel(id: "kept", accountId: kept.id, title: "T", body: "B")
        try await storage.save(deletedTemplate, id: deletedTemplate.id)
        try await storage.save(keptTemplate, id: keptTemplate.id)
        await sut.loadAccounts()

        await sut.deleteAccount(deleted)

        let remainingTemplates = try await storage.fetchAll(ReplyTemplateModel.self)
        let credentials: AppleCredentials? = keychain.object(forKey: "credentials.\(deleted.id)")
        XCTAssertEqual(remainingTemplates.map(\.id), ["kept"])
        XCTAssertNil(credentials)
        XCTAssertEqual(sut.uiState.appleAccounts.map(\.id), [kept.id])
    }

    // MARK: - Export writes appsBundles

    func testExportWritesAppsBundlesWhenNonEmpty() throws {
        let account = makeAppleAccount()
        let password = "aVeryStrongPass123"

        let url = try XCTUnwrap(sut.exportAccountWithRules(
            account: account,
            exportName: "Team",
            rules: .allPermissions,
            password: password,
            expirationDate: nil,
            appsBundles: ["com.a", "com.b"]
        ))

        let dict = try decryptPayload(at: url, password: password)
        let bundles = try XCTUnwrap(dict["appsBundles"] as? [String])
        XCTAssertEqual(Set(bundles), ["com.a", "com.b"])
    }

    func testExportOmitsAppsBundlesWhenNil() throws {
        let account = makeAppleAccount()
        let password = "aVeryStrongPass123"

        let url = try XCTUnwrap(sut.exportAccountWithRules(
            account: account,
            exportName: "Team",
            rules: .allPermissions,
            password: password,
            expirationDate: nil,
            appsBundles: nil
        ))

        let dict = try decryptPayload(at: url, password: password)
        XCTAssertNil(dict["appsBundles"])
    }

    func testExportOmitsAppsBundlesWhenEmpty() throws {
        let account = makeAppleAccount()
        let password = "aVeryStrongPass123"

        let url = try XCTUnwrap(sut.exportAccountWithRules(
            account: account,
            exportName: "Team",
            rules: .allPermissions,
            password: password,
            expirationDate: nil,
            appsBundles: []
        ))

        let dict = try decryptPayload(at: url, password: password)
        XCTAssertNil(dict["appsBundles"])
    }

    // MARK: - Import parses appsBundles

    func testImportParsesAppsBundles() async throws {
        let password = "aVeryStrongPass123"
        let payload: [String: Any] = [
            "name": "Imported",
            "providerType": "apple",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "credentials": appleCredentialsPayload(),
            "appsBundles": ["com.a", "com.c"]
        ]
        let url = try makeImportFile(payload: payload, password: password)

        let error = await sut.importAccount(from: url, password: password, customName: nil)
        XCTAssertNil(error)

        let saved = try await storage.fetchAll(AccountModel.self)
        let imported = try XCTUnwrap(saved.first { $0.origin == .imported })
        XCTAssertEqual(imported.appsBundles.map(Set.init), ["com.a", "com.c"])
        XCTAssertFalse(imported.allowsApp(bundleId: "com.b"))
        XCTAssertTrue(imported.allowsApp(bundleId: "com.a"))
    }

    func testImportLegacyFileWithoutKeyLeavesScopeNilAllowingAllApps() async throws {
        let password = "aVeryStrongPass123"
        let payload: [String: Any] = [
            "name": "Legacy",
            "providerType": "apple",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "credentials": appleCredentialsPayload()
            // no appsBundles key
        ]
        let url = try makeImportFile(payload: payload, password: password)

        let error = await sut.importAccount(from: url, password: password, customName: nil)
        XCTAssertNil(error)

        let saved = try await storage.fetchAll(AccountModel.self)
        let imported = try XCTUnwrap(saved.first { $0.origin == .imported })
        XCTAssertNil(imported.appsBundles)
        XCTAssertTrue(imported.allowsApp(bundleId: "anything"))
    }

    /// Backward-compat contract: an explicitly empty array must behave like "all apps".
    func testImportEmptyArrayAllowsAllApps() async throws {
        let password = "aVeryStrongPass123"
        let payload: [String: Any] = [
            "name": "EmptyScope",
            "providerType": "apple",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "credentials": appleCredentialsPayload(),
            "appsBundles": [String]()
        ]
        let url = try makeImportFile(payload: payload, password: password)

        let error = await sut.importAccount(from: url, password: password, customName: nil)
        XCTAssertNil(error)

        let saved = try await storage.fetchAll(AccountModel.self)
        let imported = try XCTUnwrap(saved.first { $0.origin == .imported })
        XCTAssertTrue(imported.allowsApp(bundleId: "com.whatever"))
    }

    // MARK: - Google Play (Phase 2)

    private func makeGooglePlayAccount(
        name: String = "Play Team",
        json: String = GooglePlayTestFixtures.serviceAccountJSON()
    ) -> AccountModel {
        let account = AccountModel(name: name, providerType: .googlePlay)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: "credentials.\(account.id)")
        return account
    }

    private func googlePlayImportPayload(serviceAccountJSON: String) -> [String: Any] {
        [
            "name": "Shared Play",
            "providerType": "googlePlay",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "rules": ["apps": ["view"]],
            "credentials": ["serviceAccountJSON": serviceAccountJSON],
            "appsBundles": ["com.example.one"]
        ]
    }

    func testExportGooglePlayAccountWritesTheServiceAccountJSON() throws {
        let json = GooglePlayTestFixtures.serviceAccountJSON()
        let account = makeGooglePlayAccount(json: json)
        let password = "aVeryStrongPass123"

        let url = try XCTUnwrap(sut.exportAccountWithRules(
            account: account,
            exportName: "Play Team",
            rules: AccountRules(apps: [.view]),
            password: password,
            expirationDate: nil,
            appsBundles: ["com.example.one"]
        ))

        let dict = try decryptPayload(at: url, password: password)
        XCTAssertEqual(dict["credentials"] as? [String: String], ["serviceAccountJSON": json])
        XCTAssertEqual(dict["appsBundles"] as? [String], ["com.example.one"])
    }

    func testExportFirebaseAccountProducesNoFile() {
        let account = AccountModel(name: "Firebase", providerType: .firebase)
        keychain.setObject(FirebaseCredentials(serviceAccountJSON: "{}"), forKey: "credentials.\(account.id)")

        let url = sut.exportAccountWithRules(
            account: account,
            exportName: "Firebase",
            rules: .allPermissions,
            password: "aVeryStrongPass123",
            expirationDate: nil,
            appsBundles: nil
        )

        XCTAssertNil(url)
    }

    func testAppsForExportOfAGooglePlayAccountReadsItsCachedAppList() async throws {
        let account = makeGooglePlayAccount()
        try await storage.save(
            [GooglePlayAppItem(id: "com.example.one", packageName: "com.example.one", title: "One", isManuallyAdded: false)],
            id: GooglePlayAppItem.cacheKey(accountId: account.id)
        )

        let apps = await sut.appsForExport(account: account)

        XCTAssertEqual(apps.map(\.bundleId), ["com.example.one"])
        XCTAssertEqual(apps.map(\.name), ["One"])
    }

    func testImportGooglePlayAccountRestoresScope() async throws {
        let password = "aVeryStrongPass123"
        let url = try makeImportFile(
            payload: googlePlayImportPayload(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            password: password
        )

        let error = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertNil(error)
        let imported = try XCTUnwrap(sut.uiState.googlePlayAccounts.first)
        XCTAssertEqual(imported.origin, .imported)
        XCTAssertEqual(imported.appsBundles, ["com.example.one"])
    }

    func testImportGooglePlayDuplicateByClientEmailIsRejected() async throws {
        let existing = makeGooglePlayAccount(
            name: "Existing",
            json: #"{"type":"service_account","client_email":"STACK-CONNECT@my-project.iam.gserviceaccount.com","private_key_id":"old","private_key":"-----BEGIN PRIVATE KEY-----\nA\n-----END PRIVATE KEY-----\n"}"#
        )
        try await storage.save(existing, id: existing.id)
        let password = "aVeryStrongPass123"
        let url = try makeImportFile(
            payload: googlePlayImportPayload(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            password: password
        )

        let error = await sut.importAccount(from: url, password: password, customName: "Another name")

        XCTAssertEqual(error, String(localized: "An account with these credentials already exists: \"Existing\"."))
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(saved.map(\.id), [existing.id])
    }

    func testImportGooglePlayWithMalformedKeyIsRejectedAndSavesNothing() async throws {
        let password = "aVeryStrongPass123"
        let url = try makeImportFile(
            payload: googlePlayImportPayload(serviceAccountJSON: "{ not a key"),
            password: password
        )

        let error = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertEqual(
            error,
            String(localized: "The Google Play service account key in this file is invalid. Ask the sender to export the account again.")
        )
        let saved = try await storage.fetchAll(AccountModel.self)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    // MARK: - Rename

    func testRenameKeepsTheImportedScope() async throws {
        let account = AccountModel(
            name: "Old",
            providerType: .googlePlay,
            rules: AccountRules(apps: [.view]),
            origin: .imported,
            appsBundles: ["com.example.one"]
        )
        try await storage.save(account, id: account.id)
        await sut.loadAccounts()

        await sut.updateAccountName(accountId: account.id, newName: "  New  ")

        let saved = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(saved?.name, "New")
        XCTAssertEqual(saved?.appsBundles, ["com.example.one"], "A rename must never widen the per-app scope")
        XCTAssertEqual(saved?.origin, .imported)
        XCTAssertEqual(sut.uiState.googlePlayAccounts.map(\.name), ["New"])
    }

    func testDeleteGooglePlayAccountRemovesItsCachedAppsAndCredentials() async throws {
        let account = makeGooglePlayAccount()
        try await storage.save(account, id: account.id)
        let cacheKey = GooglePlayAppItem.cacheKey(accountId: account.id)
        try await storage.save([GooglePlayAppItem(id: "com.a", packageName: "com.a", title: nil, isManuallyAdded: true)], id: cacheKey)
        await sut.loadAccounts()

        await sut.deleteAccount(account)

        let cached = try await storage.fetch([GooglePlayAppItem].self, id: cacheKey)
        XCTAssertNil(cached)
        XCTAssertNil(keychain.data(forKey: "credentials.\(account.id)"))
        XCTAssertTrue(sut.uiState.googlePlayAccounts.isEmpty)
    }
}
