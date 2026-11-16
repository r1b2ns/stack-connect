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
        sut = SettingsAccountsViewModel(storage: storage, keychain: keychain, analytics: analytics)
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
