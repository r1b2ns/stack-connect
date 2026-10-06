import XCTest
@testable import StackConnect

@MainActor
final class AccountExporterTests: XCTestCase {

    private var keychain: MockKeyStorable!
    private var storage: MockPersistentStorable!
    private var directory: URL!
    private var sut: AccountExporter!

    private let password = "aVeryStrongPass123"

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeyStorable()
        storage = MockPersistentStorable()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sut = AccountExporter(keychain: keychain, directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        sut = nil
        directory = nil
        storage = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeAppleAccount(role: AccountRole = .developer) -> AccountModel {
        let account = AccountModel(name: "Team", providerType: .apple, role: role)
        keychain.setObject(
            AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "pk"),
            forKey: "credentials.\(account.id)"
        )
        return account
    }

    private func makeGooglePlayAccount(json: String = GooglePlayTestFixtures.serviceAccountJSON()) -> AccountModel {
        let account = AccountModel(name: "Play Team", providerType: .googlePlay)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: "credentials.\(account.id)")
        return account
    }

    private func request(
        _ account: AccountModel,
        rules: AccountRules = .allPermissions,
        expirationDate: Date? = nil,
        appsBundles: [String]? = nil
    ) -> AccountExportRequest {
        AccountExportRequest(
            account: account,
            exportName: "Shared",
            rules: rules,
            password: password,
            expirationDate: expirationDate,
            appsBundles: appsBundles
        )
    }

    private func decrypt(_ url: URL) throws -> [String: Any] {
        let json = try AccountCrypto.decrypt(data: try Data(contentsOf: url), password: password)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func jsonObject(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func exportedFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    }

    // MARK: - Apple (regression)

    /// The Apple payload must be exactly what the pre-Phase-2 inline exporters
    /// produced: builder output fed with the hand-assembled credentials dict.
    func testApplePayloadIsUnchanged() throws {
        let account = makeAppleAccount()
        let expiration = Date(timeIntervalSince1970: 2_000_000_000)
        let rules = AccountRules(apps: [.view], review: [.view, .edit])

        let url = try sut.export(request(account, rules: rules, expirationDate: expiration, appsBundles: ["com.a"]))

        let legacyJSON = try XCTUnwrap(AccountExportPayloadBuilder.makeJSON(
            account: account,
            exportName: "Shared",
            rules: rules,
            expirationDate: expiration,
            appsBundles: ["com.a"],
            credentials: ["issuerID": "issuer", "privateKeyID": "kid", "privateKey": "pk"]
        ))
        let exported = try decrypt(url)
        XCTAssertEqual(NSDictionary(dictionary: exported), NSDictionary(dictionary: try jsonObject(legacyJSON)))
    }

    func testApplePayloadKeys() throws {
        let account = makeAppleAccount()

        let dict = try decrypt(try sut.export(request(account)))

        XCTAssertEqual(
            Set(dict.keys),
            ["id", "name", "providerType", "createdAt", "rules", "role", "credentials"]
        )
        XCTAssertEqual(dict["providerType"] as? String, "apple")
        XCTAssertEqual(dict["role"] as? String, "developer")
        XCTAssertEqual(dict["name"] as? String, "Shared")
        XCTAssertEqual(
            dict["credentials"] as? [String: String],
            ["issuerID": "issuer", "privateKeyID": "kid", "privateKey": "pk"]
        )
        let rules = try XCTUnwrap(dict["rules"] as? [String: [String]])
        XCTAssertEqual(
            Set(rules.keys),
            ["apps", "version", "users", "review", "testFlight", "analytics", "provisioning"]
        )
    }

    // MARK: - Google Play

    func testGooglePlayPayloadCarriesTheServiceAccountJSON() throws {
        let json = GooglePlayTestFixtures.serviceAccountJSON()
        let account = makeGooglePlayAccount(json: json)

        let dict = try decrypt(try sut.export(request(account, rules: AccountRules(apps: [.view, .add]))))

        XCTAssertEqual(dict["providerType"] as? String, "googlePlay")
        XCTAssertEqual(
            dict["credentials"] as? [String: String],
            ["serviceAccountJSON": json],
            "Same key the importers read; the stored JSON is exported as is"
        )
        let rules = try XCTUnwrap(dict["rules"] as? [String: [String]])
        XCTAssertEqual(rules["apps"], ["view", "add"])
        XCTAssertEqual(rules["version"], [])
    }

    func testGooglePlayPayloadWritesTheScope() throws {
        let account = makeGooglePlayAccount()

        let dict = try decrypt(try sut.export(request(account, appsBundles: ["com.example.one"])))

        XCTAssertEqual(dict["appsBundles"] as? [String], ["com.example.one"])
    }

    // MARK: - Not exportable

    func testFirebaseAccountIsNotExportable() throws {
        let account = AccountModel(name: "Firebase", providerType: .firebase)
        keychain.setObject(FirebaseCredentials(serviceAccountJSON: "{}"), forKey: "credentials.\(account.id)")

        XCTAssertThrowsError(try sut.export(request(account))) { error in
            XCTAssertEqual(error as? AccountExportError, .notExportable)
        }
        XCTAssertNil(AccountTransferCredentials.exportPayload(for: account, keychain: keychain))
        XCTAssertTrue(try exportedFiles().isEmpty)
    }

    func testImportedAccountIsNotExportable() throws {
        let account = AccountModel(name: "Imported", providerType: .googlePlay, origin: .imported)
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )

        XCTAssertThrowsError(try sut.export(request(account))) { error in
            XCTAssertEqual(error as? AccountExportError, .notExportable)
        }
        XCTAssertTrue(try exportedFiles().isEmpty)
    }

    func testMissingCredentialsWritesNoFile() throws {
        let account = AccountModel(name: "No keys", providerType: .googlePlay)

        XCTAssertThrowsError(try sut.export(request(account))) { error in
            XCTAssertEqual(error as? AccountExportError, .missingCredentials)
        }
        XCTAssertTrue(try exportedFiles().isEmpty)
    }

    func testExportUsesANeutralFileName() throws {
        let account = makeGooglePlayAccount()

        let url = try sut.export(request(account))

        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("export-"))
        XCTAssertEqual(url.pathExtension, "scexport")
        XCTAssertFalse(url.lastPathComponent.contains("Play"), "No account name / provider in the file name")
    }

    // MARK: - Round trip

    /// Export → decrypt → import restores the credentials, the rules and the
    /// per-app scope of a Google Play account.
    func testGooglePlayRoundTripRestoresCredentialsAndScope() async throws {
        let json = GooglePlayTestFixtures.serviceAccountJSON()
        let source = makeGooglePlayAccount(json: json)
        let rules = AccountRules(apps: [.view, .delete])
        let url = try sut.export(request(source, rules: rules, appsBundles: ["com.example.one", "com.example.two"]))

        // The recipient's device: empty keychain and storage.
        let recipientKeychain = MockKeyStorable()
        let importer = AccountImporter(storage: storage, keychain: recipientKeychain)
        let result = await importer.importAccount(from: url, password: password, customName: nil)

        let imported = try result.get()
        XCTAssertEqual(imported.providerType, .googlePlay)
        XCTAssertEqual(imported.name, "Shared")
        XCTAssertEqual(imported.origin, .imported)
        XCTAssertEqual(imported.role, .unspecified)
        XCTAssertEqual(imported.rules, rules)
        XCTAssertEqual(imported.appsBundles.map(Set.init), ["com.example.one", "com.example.two"])
        XCTAssertTrue(imported.allowsApp(bundleId: "com.example.one"))
        XCTAssertFalse(imported.allowsApp(bundleId: "com.example.other"))

        let restored: GooglePlayCredentials? = recipientKeychain.object(forKey: "credentials.\(imported.id)")
        XCTAssertEqual(restored?.serviceAccountJSON, json)
        let saved = try await storage.fetch(AccountModel.self, id: imported.id)
        XCTAssertEqual(saved?.appsBundles.map(Set.init), ["com.example.one", "com.example.two"])
    }

    func testGooglePlayRoundTripWithoutScopeAllowsEveryApp() async throws {
        let url = try sut.export(request(makeGooglePlayAccount(), appsBundles: []))

        let importer = AccountImporter(storage: storage, keychain: MockKeyStorable())
        let imported = try await importer.importAccount(from: url, password: password, customName: nil).get()

        XCTAssertNil(imported.appsBundles)
        XCTAssertTrue(imported.allowsApp(bundleId: "com.anything"))
    }
}
