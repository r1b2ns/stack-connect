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
}
