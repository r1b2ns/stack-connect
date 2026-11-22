import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class SettingsAccountsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private var sut: SettingsAccountsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        sut = SettingsAccountsViewModel(storage: storage, keychain: keychain, analytics: analytics, featureFlags: .googlePlayOn)
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
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

    // MARK: - Sections by provider and connection kind

    private func connections(_ provider: ProviderType, _ kinds: [AccountConnectionKind]) -> [AccountConnection] {
        kinds.map { AccountConnection(provider: provider, kind: $0) }
    }

    func testAppleAccountsAreSplitIntoAPIKeyThenAppleIDSectionsInNameOrder() async throws {
        let sessionB = AccountModel(name: "Session B", providerType: .apple, authMethod: .appleIdSignIn)
        let keyZ = AccountModel(name: "Key Z", providerType: .apple)
        let sessionA = AccountModel(name: "Session A", providerType: .apple, authMethod: .appleIdSignIn)
        let keyA = AccountModel(name: "Key A", providerType: .apple)
        for account in [sessionB, keyZ, sessionA, keyA] {
            try await storage.save(account, id: account.id)
        }

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.sections.map(\.connection), connections(.apple, [.keyFile, .signIn]))
        XCTAssertEqual(sut.uiState.sections.map { $0.accounts.map(\.name) }, [["Key A", "Key Z"], ["Session A", "Session B"]])
        XCTAssertEqual(sut.uiState.appleAccounts.count, 4)
    }

    func testGoogleAccountsAreSplitIntoServiceAccountKeyThenGoogleAccountSectionsInNameOrder() async throws {
        let accounts = [
            AccountModel(name: "Play Signed In", providerType: .googlePlay, authMethod: .googleSignIn),
            AccountModel(name: "Firebase Signed In", providerType: .firebase, authMethod: .googleSignIn),
            AccountModel(name: "Play Key B", providerType: .googlePlay),
            AccountModel(name: "Firebase Key", providerType: .firebase),
            AccountModel(name: "Play Key A", providerType: .googlePlay),
        ]
        for account in accounts {
            try await storage.save(account, id: account.id)
        }

        await sut.loadAccounts()

        XCTAssertEqual(
            sut.uiState.sections.map(\.connection),
            connections(.firebase, [.keyFile, .signIn]) + connections(.googlePlay, [.keyFile, .signIn])
        )
        XCTAssertEqual(
            sut.uiState.sections.map { $0.accounts.map(\.name) },
            [["Firebase Key"], ["Firebase Signed In"], ["Play Key A", "Play Key B"], ["Play Signed In"]]
        )
        XCTAssertEqual(Set(sut.uiState.sections.map(\.id)).count, 4, "Section ids are unique")
        XCTAssertEqual(sut.uiState.firebaseAccounts.count, 2)
        XCTAssertEqual(sut.uiState.googlePlayAccounts.count, 3)
    }

    func testSectionsAreOrderedAppleThenFirebaseThenGooglePlay() async throws {
        let accounts = [
            AccountModel(name: "Play", providerType: .googlePlay, authMethod: .googleSignIn),
            AccountModel(name: "Firebase", providerType: .firebase),
            AccountModel(name: "Session", providerType: .apple, authMethod: .appleIdSignIn),
        ]
        for account in accounts {
            try await storage.save(account, id: account.id)
        }

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.sections.map(\.connection), [
            AccountConnection(provider: .apple, kind: .signIn),
            AccountConnection(provider: .firebase, kind: .keyFile),
            AccountConnection(provider: .googlePlay, kind: .signIn),
        ])
    }

    func testOnlyNonEmptySectionsAreShown() async throws {
        let key = AccountModel(name: "Key", providerType: .apple)
        let play = AccountModel(name: "Play", providerType: .googlePlay)
        try await storage.save(key, id: key.id)
        try await storage.save(play, id: play.id)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.sections.map(\.connection), [
            AccountConnection(provider: .apple, kind: .keyFile),
            AccountConnection(provider: .googlePlay, kind: .keyFile),
        ])
    }

    func testNoSectionsWithoutAccounts() async {
        await sut.loadAccounts()

        XCTAssertTrue(sut.uiState.sections.isEmpty)
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

    func testHidesGooglePlayAccountsAndProviderWhileGooglePlayIsHidden() async throws {
        let hidden = SettingsAccountsViewModel(storage: storage, keychain: keychain, analytics: analytics, featureFlags: .googlePlayOff)
        let play = AccountModel(id: "play", name: "Play", providerType: .googlePlay)
        try await storage.save(play, id: play.id)
        try await storage.save(AccountModel(id: "asc", name: "ASC", providerType: .apple), id: "asc")

        await hidden.loadAccounts()

        XCTAssertTrue(hidden.uiState.googlePlayAccounts.isEmpty)
        XCTAssertEqual(hidden.uiState.appleAccounts.map(\.id), ["asc"])
        XCTAssertEqual(hidden.uiState.availableProviders, [.apple, .firebase])
        XCTAssertEqual(sut.uiState.availableProviders, ProviderType.allCases, "Flag ON offers Google Play")
        let stored = try await storage.fetch(AccountModel.self, id: "play")
        XCTAssertNotNil(stored, "A hidden account is never deleted")
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

        // Interpolated like production so the lookup hits the localized "%@" key.
        let existingName = existing.name
        XCTAssertEqual(error, String(localized: "An account with these credentials already exists: \"\(existingName)\"."))
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

    // MARK: - Analytics events

    func testDeleteAccountTracksConfirmTapAndSuccess() async throws {
        let account = makeAppleAccount()
        try await storage.save(account, id: account.id)

        await sut.deleteAccount(account)

        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .settingsAccounts)])
        XCTAssertEqual(analytics.actions(of: .deleteAccount), [
            .action(.deleteAccount, on: .settingsAccounts, result: .success, parameters: [
                AnalyticsParameterKey.kind: .string(ProviderType.apple.rawValue)
            ])
        ])
    }

    func testDeleteAccountTracksFailure() async throws {
        let account = makeAppleAccount()
        try await storage.save(account, id: account.id)
        await storage.failDelete(AccountModel.self, id: account.id)

        await sut.deleteAccount(account)

        XCTAssertEqual(analytics.results(of: .deleteAccount), [.failure])
    }

    func testExportTracksSuccessWithShapeOnly() throws {
        let account = makeAppleAccount()

        _ = sut.exportAccountWithRules(
            account: account,
            exportName: "Team",
            rules: .allPermissions,
            password: "aVeryStrongPass123",
            expirationDate: .now,
            appsBundles: ["com.a"]
        )

        XCTAssertEqual(analytics.actions(of: .exportAccount), [
            .action(.exportAccount, on: .exportAccount, result: .success, parameters: [
                AnalyticsParameterKey.hasExpiration: .bool(true),
                AnalyticsParameterKey.scoped: .bool(true)
            ])
        ])
    }

    func testImportTracksSuccess() async throws {
        let password = "aVeryStrongPass123"
        let payload: [String: Any] = [
            "name": "Imported",
            "providerType": "apple",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "credentials": appleCredentialsPayload()
        ]
        let url = try makeImportFile(payload: payload, password: password)

        _ = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertEqual(analytics.taps(of: .confirmImport).count, 1)
        XCTAssertEqual(analytics.results(of: .importAccount), [.success])
        XCTAssertNil(analytics.actions(of: .importAccount).first?.parameters[AnalyticsParameterKey.errorCategory])
    }

    func testImportTracksFailureWithWrongPassword() async throws {
        let payload: [String: Any] = [
            "name": "Imported",
            "providerType": "apple",
            "credentials": appleCredentialsPayload()
        ]
        let url = try makeImportFile(payload: payload, password: "aVeryStrongPass123")

        let error = await sut.importAccount(from: url, password: "wrong-password", customName: nil)

        XCTAssertNotNil(error)
        XCTAssertEqual(analytics.results(of: .importAccount), [.failure])
        XCTAssertEqual(
            analytics.actions(of: .importAccount).first?.parameters[AnalyticsParameterKey.errorCategory],
            .string("wrong_password"),
            "Only the category is sent, never the error message"
        )
    }

    func testRenameAccountTracksSaveTapAndSuccess() async throws {
        let account = makeAppleAccount()
        try await storage.save(account, id: account.id)
        await sut.loadAccounts()

        await sut.updateAccountName(accountId: account.id, newName: "Renamed")

        XCTAssertEqual(analytics.taps(of: .save), [.buttonTap(.save, on: .settingsAccountEdit)])
        XCTAssertEqual(analytics.results(of: .saveAccount), [.success])
    }

    func testRenameUnknownAccountTracksFailure() async {
        await sut.updateAccountName(accountId: "missing", newName: "Renamed")

        XCTAssertEqual(analytics.results(of: .saveAccount), [.failure])
    }
}
