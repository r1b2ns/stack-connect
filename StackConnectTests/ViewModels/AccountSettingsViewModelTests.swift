import XCTest
@testable import StackConnect

@MainActor
final class AccountSettingsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var keychain: MockKeyStorable!

    private let password = "aVeryStrongPass123"

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        keychain = MockKeyStorable()
    }

    override func tearDown() async throws {
        storage = nil
        keychain = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT(_ account: AccountModel) -> AccountSettingsViewModel {
        AccountSettingsViewModel(account: account, storage: storage, keychain: keychain)
    }

    private func makeGooglePlayAccount(json: String = GooglePlayTestFixtures.serviceAccountJSON()) -> AccountModel {
        let account = AccountModel(name: "Play Team", providerType: .googlePlay)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: "credentials.\(account.id)")
        return account
    }

    private func decryptPayload(at url: URL) throws -> [String: Any] {
        let json = try AccountCrypto.decrypt(data: try Data(contentsOf: url), password: password)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    // MARK: - Export

    func testExportGooglePlayAccountWritesTheServiceAccountJSON() throws {
        let json = GooglePlayTestFixtures.serviceAccountJSON()
        let sut = makeSUT(makeGooglePlayAccount(json: json))

        let url = try XCTUnwrap(sut.exportAccountWithRules(
            exportName: "Shared",
            rules: AccountRules(apps: [.view]),
            password: password,
            expirationDate: nil,
            appsBundles: ["com.example.one"]
        ))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let dict = try decryptPayload(at: url)
        XCTAssertEqual(dict["providerType"] as? String, "googlePlay")
        XCTAssertEqual(dict["credentials"] as? [String: String], ["serviceAccountJSON": json])
        XCTAssertEqual(dict["appsBundles"] as? [String], ["com.example.one"])
    }

    func testExportAppleAccountKeepsItsCredentialKeys() throws {
        let account = AccountModel(name: "Team", providerType: .apple)
        keychain.setObject(
            AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "pk"),
            forKey: "credentials.\(account.id)"
        )
        let sut = makeSUT(account)

        let url = try XCTUnwrap(sut.exportAccountWithRules(
            exportName: "Team",
            rules: .allPermissions,
            password: password,
            expirationDate: nil,
            appsBundles: nil
        ))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let dict = try decryptPayload(at: url)
        XCTAssertEqual(
            dict["credentials"] as? [String: String],
            ["issuerID": "issuer", "privateKeyID": "kid", "privateKey": "pk"]
        )
        XCTAssertNil(dict["appsBundles"])
    }

    func testAppsForExportOfAGooglePlayAccountReadsItsCachedAppList() async throws {
        let account = makeGooglePlayAccount()
        try await storage.save(
            [GooglePlayAppItem(id: "com.b", packageName: "com.b", title: nil, isManuallyAdded: true)],
            id: GooglePlayAppItem.cacheKey(accountId: account.id)
        )

        let apps = await makeSUT(account).appsForExport()

        XCTAssertEqual(apps.map(\.bundleId), ["com.b"])
    }

    // MARK: - Save (rename / role)

    func testRenameKeepsTheImportedScope() async throws {
        let account = AccountModel(
            name: "Old",
            providerType: .apple,
            origin: .imported,
            role: .developer,
            appsBundles: ["com.a"]
        )
        let sut = makeSUT(account)
        sut.uiState.editingName = "New"

        await sut.save()

        let saved = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(saved?.name, "New")
        XCTAssertEqual(saved?.role, .developer)
        XCTAssertEqual(saved?.appsBundles, ["com.a"], "A rename must never widen the per-app scope")
        XCTAssertEqual(sut.uiState.account.appsBundles, ["com.a"])
    }

    func testSaveUpdatesTheAppleRole() async throws {
        let account = AccountModel(name: "Team", providerType: .apple)
        let sut = makeSUT(account)
        sut.uiState.editingRole = .admin

        await sut.save()

        let saved = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(saved?.role, .admin)
    }

    func testSaveRenamesAGooglePlayAccountAndKeepsItsDefaultRole() async throws {
        let account = makeGooglePlayAccount()
        let sut = makeSUT(account)
        sut.uiState.editingName = "Renamed"
        sut.uiState.editingRole = .admin // Not editable for Google Play.

        await sut.save()

        let saved = try await storage.fetch(AccountModel.self, id: account.id)
        XCTAssertEqual(saved?.name, "Renamed")
        XCTAssertEqual(saved?.role, .unspecified)
        XCTAssertNotNil(sut.uiState.toastMessage)
    }
}
