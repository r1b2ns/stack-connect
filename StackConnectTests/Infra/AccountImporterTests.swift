import XCTest
@testable import StackConnect

@MainActor
final class AccountImporterTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!
    private var sut: AccountImporter!

    private let password = "aVeryStrongPass123"

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
        sut = AccountImporter(storage: storage, keychain: keychain)
    }

    override func tearDown() async throws {
        sut = nil
        keychain = nil
        storage = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeImportFile(_ payload: [String: Any]) throws -> URL {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let encrypted = try AccountCrypto.encrypt(json: String(decoding: jsonData, as: UTF8.self), password: password)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).scexport")
        try encrypted.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func googlePlayPayload(
        serviceAccountJSON: String = GooglePlayTestFixtures.serviceAccountJSON(),
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "name": "Shared Play",
            "providerType": "googlePlay",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "rules": ["apps": ["view"]],
            "credentials": ["serviceAccountJSON": serviceAccountJSON]
        ]
        payload.merge(extra) { _, new in new }
        return payload
    }

    /// Stores an existing Google Play account whose key is `json`.
    @discardableResult
    private func seedGooglePlayAccount(name: String = "Existing", json: String) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: .googlePlay)
        try await storage.save(account, id: account.id)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: "credentials.\(account.id)")
        return account
    }

    private func importFile(
        _ payload: [String: Any],
        customName: String? = nil,
        options: AccountImporter.Options = AccountImporter.Options()
    ) async throws -> Result<AccountModel, AccountImportError> {
        let url = try makeImportFile(payload)
        return await sut.importAccount(from: url, password: password, customName: customName, options: options)
    }

    private func storedAccounts() async throws -> [AccountModel] {
        try await storage.fetchAll(AccountModel.self)
    }

    private let duplicateError = String(
        localized: "An account with these credentials already exists: \"Existing\"."
    )

    // MARK: - Google Play success

    func testImportsAGooglePlayAccount() async throws {
        let json = GooglePlayTestFixtures.serviceAccountJSON()

        let imported = try await importFile(googlePlayPayload(serviceAccountJSON: json)).get()

        XCTAssertEqual(imported.providerType, .googlePlay)
        XCTAssertEqual(imported.name, "Shared Play")
        XCTAssertEqual(imported.origin, .imported)
        XCTAssertEqual(imported.rules.apps, [.view])
        let stored: GooglePlayCredentials? = keychain.object(forKey: "credentials.\(imported.id)")
        XCTAssertEqual(stored?.serviceAccountJSON, json, "Storage format unchanged: the whole key file")
        let accounts = try await storedAccounts()
        XCTAssertEqual(accounts.map(\.id), [imported.id])
    }

    func testGooglePlayRoleInTheFileIsIgnored() async throws {
        let imported = try await importFile(googlePlayPayload(extra: ["role": "admin"])).get()

        XCTAssertEqual(imported.role, .unspecified, "Google Play accounts keep the default role")
    }

    func testCustomNameWins() async throws {
        let imported = try await importFile(googlePlayPayload(), customName: "  Mine  ").get()

        XCTAssertEqual(imported.name, "Mine")
    }

    // MARK: - Google Play duplicates (client_email)

    func testSameServiceAccountWithDifferentFormattingIsADuplicate() async throws {
        // Stored compact, with an upper-cased e-mail and an older key id.
        let storedJSON = #"{"type":"service_account","client_email":"STACK-CONNECT@my-project.iam.gserviceaccount.com","private_key_id":"old-key","private_key":"-----BEGIN PRIVATE KEY-----\nA\n-----END PRIVATE KEY-----\n"}"#
        try await seedGooglePlayAccount(json: storedJSON)
        let keysBefore = keychain.storedKeys

        // Imported pretty-printed, lower-cased e-mail, new key id.
        let result = try await importFile(googlePlayPayload(
            serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON(privateKeyId: "new-key")
        ), customName: "Another name")

        XCTAssertEqual(result, .failure(AccountImportError(message: duplicateError)))
        let accounts = try await storedAccounts()
        XCTAssertEqual(accounts.count, 1, "Nothing saved")
        XCTAssertEqual(keychain.storedKeys, keysBefore, "No credentials written")
    }

    func testDifferentServiceAccountIsNotADuplicate() async throws {
        try await seedGooglePlayAccount(
            json: GooglePlayTestFixtures.serviceAccountJSON(clientEmail: "other@proj.iam.gserviceaccount.com")
        )

        let result = try await importFile(googlePlayPayload())

        XCTAssertNoThrow(try result.get())
        let accounts = try await storedAccounts()
        XCTAssertEqual(accounts.count, 2)
    }

    func testReimportReplacingTheSameServiceAccountIsAllowed() async throws {
        let existing = try await seedGooglePlayAccount(json: GooglePlayTestFixtures.serviceAccountJSON())

        let imported = try await importFile(
            googlePlayPayload(),
            options: AccountImporter.Options(expectedProvider: .googlePlay, replacingAccountId: existing.id)
        ).get()

        XCTAssertEqual(imported.id, existing.id, "Replaced in place")
        let accounts = try await storedAccounts()
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.origin, .imported)
    }

    // MARK: - Google Play malformed key

    func testMalformedServiceAccountJSONIsRejectedAndNothingIsSaved() async throws {
        let result = try await importFile(googlePlayPayload(serviceAccountJSON: #"{"type": "service_account", "client_email": "#))

        XCTAssertEqual(result, .failure(AccountImportError(
            message: String(localized: "The Google Play service account key in this file is invalid. Ask the sender to export the account again.")
        )))
        let accounts = try await storedAccounts()
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    func testServiceAccountJSONMissingAFieldIsRejected() async throws {
        let result = try await importFile(googlePlayPayload(
            serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON(privateKey: nil)
        ))

        XCTAssertThrowsError(try result.get())
        let accounts = try await storedAccounts()
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    func testMissingServiceAccountJSONKeepsTheLegacyMessage() async throws {
        var payload = googlePlayPayload()
        payload["credentials"] = ["somethingElse": "x"]

        let result = try await importFile(payload)

        XCTAssertEqual(result, .failure(AccountImportError(
            message: String(localized: "Invalid Google Play credentials. Required: serviceAccountJSON.")
        )))
    }

    // MARK: - Provider filter

    func testExpectedProviderRejectsOtherProviders() async throws {
        let result = try await importFile(
            googlePlayPayload(),
            options: AccountImporter.Options(expectedProvider: .apple)
        )

        XCTAssertEqual(result, .failure(AccountImportError(
            message: String(localized: "This file contains a \(ProviderType.googlePlay.displayName) account, but this is the \(ProviderType.apple.displayName) section.")
        )))
        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    // MARK: - Apple (regression)

    func testAppleImportStillWorks() async throws {
        let payload: [String: Any] = [
            "name": "Team",
            "providerType": "apple",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "role": "developer",
            "credentials": ["issuerID": "issuer", "privateKeyID": "kid", "privateKey": "pk"]
        ]

        let imported = try await importFile(payload).get()

        XCTAssertEqual(imported.role, .developer)
        XCTAssertEqual(imported.rules, AccountRules(), "Absent rules ⇒ no permissions")
        XCTAssertNil(imported.appsBundles)
        let stored: AppleCredentials? = keychain.object(forKey: "credentials.\(imported.id)")
        XCTAssertEqual(stored?.issuerID, "issuer")
        XCTAssertEqual(stored?.privateKey, "pk")
    }
}
