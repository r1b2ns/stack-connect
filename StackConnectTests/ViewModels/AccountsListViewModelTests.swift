import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AccountsListViewModelTests: XCTestCase {

    private var sut: AccountsListViewModel!
    private var mockStorage: MockPersistentStorable!
    private var mockKeychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!

    override func setUp() async throws {
        try await super.setUp()
        mockStorage = MockPersistentStorable()
        mockKeychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        sut = AccountsListViewModel(
            providerType: .apple,
            storage: mockStorage,
            keychain: mockKeychain,
            analytics: analytics
        )
    }

    override func tearDown() async throws {
        sut = nil
        analytics = nil
        mockStorage = nil
        mockKeychain = nil
        try await super.tearDown()
    }

    // MARK: - Load

    func testLoadAccountsFiltersbyProviderType() async throws {
        let apple = AccountModel(name: "Apple Account", providerType: .apple)
        let firebase = AccountModel(name: "Firebase Account", providerType: .firebase)
        try await mockStorage.save(apple, id: apple.id)
        try await mockStorage.save(firebase, id: firebase.id)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.accounts.count, 1)
        XCTAssertEqual(sut.uiState.accounts.first?.name, "Apple Account")
    }

    func testLoadAccountsEmptyState() async {
        await sut.loadAccounts()
        XCTAssertTrue(sut.uiState.accounts.isEmpty)
        XCTAssertFalse(sut.uiState.isLoading)
    }

    // MARK: - Delete

    func testDeleteAccountRemovesFromStorageAndKeychain() async throws {
        let account = AccountModel(name: "ToDelete", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        mockKeychain.set("secret", forKey: "credentials.\(account.id)")

        await sut.loadAccounts()
        XCTAssertEqual(sut.uiState.accounts.count, 1)

        await sut.deleteAccount(at: IndexSet(integer: 0))

        XCTAssertTrue(sut.uiState.accounts.isEmpty)
        XCTAssertNil(mockKeychain.string(forKey: "credentials.\(account.id)"))
    }

    // MARK: - Delete cascades to reply templates

    private func seedTemplate(id: String, accountId: String) async throws {
        let template = ReplyTemplateModel(id: id, accountId: accountId, title: "Title", body: "Body")
        try await mockStorage.save(template, id: template.id)
    }

    private func storedTemplates() async throws -> [ReplyTemplateModel] {
        try await mockStorage.fetchAll(ReplyTemplateModel.self)
    }

    func testDeleteAccountRemovesItsReplyTemplatesAndKeepsOthers() async throws {
        let deleted = AccountModel(name: "Deleted", providerType: .apple)
        let kept = AccountModel(name: "Kept", providerType: .apple)
        try await mockStorage.save(deleted, id: deleted.id)
        try await mockStorage.save(kept, id: kept.id)
        try await seedTemplate(id: "deleted-1", accountId: deleted.id)
        try await seedTemplate(id: "deleted-2", accountId: deleted.id)
        try await seedTemplate(id: "kept-1", accountId: kept.id)
        await sut.loadAccounts()

        await sut.deleteAccount(deleted)

        let remaining = try await storedTemplates()
        XCTAssertEqual(remaining.map(\.id), ["kept-1"])
        XCTAssertEqual(remaining.first?.accountId, kept.id)
        XCTAssertEqual(sut.uiState.accounts.map(\.id), [kept.id])
    }

    func testDeleteAccountAtOffsetsRemovesItsReplyTemplates() async throws {
        let account = AccountModel(name: "Swiped", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        try await seedTemplate(id: "t1", accountId: account.id)
        await sut.loadAccounts()

        await sut.deleteAccount(at: IndexSet(integer: 0))

        let remaining = try await storedTemplates()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(sut.uiState.accounts.isEmpty)
    }

    // MARK: - Grouping by team / issuerID (issue #66)

    private func storeAppleCredentials(issuerID: String, for accountId: String) {
        mockKeychain.setObject(
            AppleCredentials(issuerID: issuerID, privateKeyID: "kid", privateKey: "key"),
            forKey: "credentials.\(accountId)"
        )
    }

    func testGroupsSameIssuerIDIntoOneGroup() async throws {
        let a = AccountModel(name: "Team A — Admin", providerType: .apple)
        let b = AccountModel(name: "Team A — Developer", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-shared", for: a.id)
        storeAppleCredentials(issuerID: "issuer-shared", for: b.id)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.count, 1)
        let group = try XCTUnwrap(sut.uiState.groups.first)
        XCTAssertEqual(group.issuerID, "issuer-shared")
        XCTAssertEqual(group.accounts.count, 2)
        // Sorted by name within the group
        XCTAssertEqual(group.accounts.map(\.name), ["Team A — Admin", "Team A — Developer"])
    }

    func testGroupsDifferentIssuerIDsIntoSeparateGroups() async throws {
        let a = AccountModel(name: "Team A", providerType: .apple)
        let b = AccountModel(name: "Team B", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-aaa", for: a.id)
        storeAppleCredentials(issuerID: "issuer-bbb", for: b.id)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.count, 2)
        let issuerIDs = sut.uiState.groups.compactMap(\.issuerID).sorted()
        XCTAssertEqual(issuerIDs, ["issuer-aaa", "issuer-bbb"])
        XCTAssertTrue(sut.uiState.groups.allSatisfy { $0.accounts.count == 1 })
    }

    func testAppleAccountWithoutReadableCredentialsFallsIntoUnknownGroup() async throws {
        let a = AccountModel(name: "Orphan", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        // No credentials stored in keychain → issuerID unreadable.

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.groups.count, 1)
        let group = try XCTUnwrap(sut.uiState.groups.first)
        XCTAssertNil(group.issuerID)
        XCTAssertEqual(group.id, "unknown")
        XCTAssertEqual(group.accounts.first?.name, "Orphan")
    }

    func testShowsTeamGroupsWhenATeamHasMoreThanOneAccount() async throws {
        let a = AccountModel(name: "Team A — Admin", providerType: .apple)
        let b = AccountModel(name: "Team A — Developer", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-shared", for: a.id)
        storeAppleCredentials(issuerID: "issuer-shared", for: b.id)

        await sut.loadAccounts()

        XCTAssertTrue(sut.uiState.showsTeamGroups)
    }

    func testHidesTeamGroupsWhenEveryTeamHasASingleAccount() async throws {
        let a = AccountModel(name: "Team A", providerType: .apple)
        let b = AccountModel(name: "Team B", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-aaa", for: a.id)
        storeAppleCredentials(issuerID: "issuer-bbb", for: b.id)

        await sut.loadAccounts()

        // Two distinct teams, one account each → no team headers.
        XCTAssertFalse(sut.uiState.showsTeamGroups)
    }

    func testDeleteAccountSingleRemovesFromStorageAndKeychainAndRebuildsGroups() async throws {
        let a = AccountModel(name: "Team A", providerType: .apple)
        let b = AccountModel(name: "Team B", providerType: .apple)
        try await mockStorage.save(a, id: a.id)
        try await mockStorage.save(b, id: b.id)
        storeAppleCredentials(issuerID: "issuer-aaa", for: a.id)
        storeAppleCredentials(issuerID: "issuer-bbb", for: b.id)

        await sut.loadAccounts()
        XCTAssertEqual(sut.uiState.groups.count, 2)

        await sut.deleteAccount(a)

        XCTAssertEqual(sut.uiState.accounts.count, 1)
        XCTAssertEqual(sut.uiState.accounts.first?.name, "Team B")
        XCTAssertNil(mockKeychain.data(forKey: "credentials.\(a.id)"))
        XCTAssertEqual(sut.uiState.groups.count, 1)
        XCTAssertEqual(sut.uiState.groups.first?.issuerID, "issuer-bbb")
    }

    // MARK: - Sections by connection kind (API Key / Apple ID)

    private func storeAppleIdSession(teamId: UInt64, for accountId: String) {
        mockKeychain.setObject(
            AppleCredentials(webSession: AppleWebSessionReference(appleId: "dev@example.com", teamId: teamId, teamName: "Team \(teamId)")),
            forKey: "credentials.\(accountId)"
        )
    }

    @discardableResult
    private func seedAPIKeyAccount(_ name: String, issuerID: String) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        storeAppleCredentials(issuerID: issuerID, for: account.id)
        return account
    }

    @discardableResult
    private func seedAppleIdAccount(_ name: String, teamId: UInt64) async throws -> AccountModel {
        let account = AccountModel(name: name, providerType: .apple, authMethod: .appleIdSignIn)
        try await mockStorage.save(account, id: account.id)
        storeAppleIdSession(teamId: teamId, for: account.id)
        return account
    }

    func testSplitsAppleAccountsIntoAPIKeyThenAppleIDSections() async throws {
        try await seedAppleIdAccount("Session B", teamId: 2)
        try await seedAPIKeyAccount("Key Z", issuerID: "issuer-zzz")
        try await seedAppleIdAccount("Session A", teamId: 1)
        try await seedAPIKeyAccount("Key A", issuerID: "issuer-aaa")

        await sut.loadAccounts()

        XCTAssertFalse(sut.uiState.showsTeamGroups)
        XCTAssertEqual(sut.uiState.sections.map(\.connection), [.apiKey, .appleId])
        XCTAssertEqual(sut.uiState.sections.map { $0.accounts.map(\.name) }, [["Key A", "Key Z"], ["Session A", "Session B"]])
        XCTAssertTrue(sut.uiState.sections.allSatisfy { $0.issuerID == nil })
    }

    func testShowsOnlyTheAPIKeySectionWithItsHeaderWhenThereAreNoAppleIDAccounts() async throws {
        try await seedAPIKeyAccount("Key A", issuerID: "issuer-aaa")
        try await seedAPIKeyAccount("Key B", issuerID: "issuer-bbb")

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.sections.count, 1)
        XCTAssertEqual(sut.uiState.sections.first?.connection, .apiKey)
        XCTAssertEqual(sut.uiState.sections.first?.accounts.map(\.name), ["Key A", "Key B"])
    }

    func testShowsOnlyTheAppleIDSectionWithItsHeaderWhenThereAreNoAPIKeyAccounts() async throws {
        try await seedAppleIdAccount("Session", teamId: 1)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.sections.map(\.connection), [.appleId])
        XCTAssertEqual(sut.uiState.sections.first?.accounts.map(\.name), ["Session"])
    }

    func testAPIKeyAccountWithUnreadableCredentialsStaysInTheAPIKeySection() async throws {
        let orphan = AccountModel(name: "Orphan", providerType: .apple)
        try await mockStorage.save(orphan, id: orphan.id)
        try await seedAppleIdAccount("Session", teamId: 1)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.sections.map(\.connection), [.apiKey, .appleId])
        XCTAssertEqual(sut.uiState.sections.first?.accounts.map(\.name), ["Orphan"])
    }

    func testTeamGroupsAreSplitInsideTheirConnectionSection() async throws {
        try await seedAPIKeyAccount("A — Admin", issuerID: "issuer-aaa")
        try await seedAPIKeyAccount("A — Developer", issuerID: "issuer-aaa")
        try await seedAPIKeyAccount("B", issuerID: "issuer-bbb")
        try await seedAppleIdAccount("Session", teamId: 1)

        await sut.loadAccounts()

        XCTAssertTrue(sut.uiState.showsTeamGroups)
        let sections = sut.uiState.sections
        XCTAssertEqual(sections.map(\.connection), [.apiKey, nil, .appleId], "Only the first team section of a connection shows its header")
        XCTAssertEqual(sections.map(\.issuerID), ["issuer-aaa", "issuer-bbb", nil])
        XCTAssertEqual(sections.map { $0.accounts.map(\.name) }, [["A — Admin", "A — Developer"], ["B"], ["Session"]])
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count, "Section ids are unique")
    }

    func testDeletingTheLastAppleIDAccountRemovesItsSection() async throws {
        try await seedAPIKeyAccount("Key", issuerID: "issuer-aaa")
        let session = try await seedAppleIdAccount("Session", teamId: 1)
        await sut.loadAccounts()
        XCTAssertEqual(sut.uiState.sections.map(\.connection), [.apiKey, .appleId])

        await sut.deleteAccount(session)

        XCTAssertEqual(sut.uiState.sections.map(\.connection), [.apiKey])
    }

    func testOtherProvidersHaveASingleSectionWithoutHeaders() async throws {
        let sut = makeGooglePlaySUT()
        let b = AccountModel(name: "Play B", providerType: .googlePlay)
        let a = AccountModel(name: "Play A", providerType: .googlePlay, authMethod: .googleSignIn)
        try await mockStorage.save(b, id: b.id)
        try await mockStorage.save(a, id: a.id)

        await sut.loadAccounts()

        XCTAssertEqual(sut.uiState.sections.count, 1)
        let section = try XCTUnwrap(sut.uiState.sections.first)
        XCTAssertNil(section.connection)
        XCTAssertNil(section.issuerID)
        XCTAssertEqual(section.accounts.map(\.name), ["Play A", "Play B"])
    }

    // MARK: - Google Play import (Phase 2)

    private let password = "aVeryStrongPass123"

    private func makeGooglePlaySUT() -> AccountsListViewModel {
        AccountsListViewModel(providerType: .googlePlay, storage: mockStorage, keychain: mockKeychain, featureFlags: .googlePlayOn)
    }

    private func makeImportFile(_ payload: [String: Any]) throws -> URL {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let encrypted = try AccountCrypto.encrypt(json: String(decoding: jsonData, as: UTF8.self), password: password)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).scexport")
        try encrypted.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func googlePlayPayload(serviceAccountJSON: String = GooglePlayTestFixtures.serviceAccountJSON()) -> [String: Any] {
        [
            "name": "Shared Play",
            "providerType": "googlePlay",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "rules": ["apps": ["view"]],
            "role": "admin",
            "credentials": ["serviceAccountJSON": serviceAccountJSON],
            "appsBundles": ["com.example.one"]
        ]
    }

    func testGooglePlayListIsEmptyWhileGooglePlayIsHidden() async throws {
        let hidden = AccountsListViewModel(providerType: .googlePlay, storage: mockStorage, keychain: mockKeychain, featureFlags: .googlePlayOff)
        try await mockStorage.save(AccountModel(id: "play", name: "Play", providerType: .googlePlay), id: "play")

        await hidden.loadAccounts()

        XCTAssertTrue(hidden.uiState.accounts.isEmpty)
        XCTAssertTrue(hidden.uiState.groups.isEmpty)
    }

    func testImportGooglePlayAccountRestoresCredentialsAndScope() async throws {
        let json = GooglePlayTestFixtures.serviceAccountJSON()
        let sut = makeGooglePlaySUT()
        let url = try makeImportFile(googlePlayPayload(serviceAccountJSON: json))

        let error = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertNil(error)
        let imported = try XCTUnwrap(sut.uiState.accounts.first)
        XCTAssertEqual(imported.providerType, .googlePlay)
        XCTAssertEqual(imported.origin, .imported)
        XCTAssertEqual(imported.role, .unspecified, "Google Play accounts keep the default role")
        XCTAssertEqual(imported.appsBundles, ["com.example.one"])
        let stored: GooglePlayCredentials? = mockKeychain.object(forKey: "credentials.\(imported.id)")
        XCTAssertEqual(stored?.serviceAccountJSON, json)
    }

    func testImportGooglePlayDuplicateByClientEmailIsRejected() async throws {
        let existing = AccountModel(name: "Existing", providerType: .googlePlay)
        try await mockStorage.save(existing, id: existing.id)
        let storedJSON = #"{"type":"service_account","client_email":"STACK-CONNECT@my-project.iam.gserviceaccount.com","private_key_id":"old","private_key":"-----BEGIN PRIVATE KEY-----\nA\n-----END PRIVATE KEY-----\n"}"#
        mockKeychain.setObject(GooglePlayCredentials(serviceAccountJSON: storedJSON), forKey: "credentials.\(existing.id)")
        let sut = makeGooglePlaySUT()
        let url = try makeImportFile(googlePlayPayload(
            serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON(privateKeyId: "new")
        ))

        let error = await sut.importAccount(from: url, password: password, customName: "Another name")

        XCTAssertEqual(error, String(localized: "An account with these credentials already exists: \"Existing\"."))
        let saved = try await mockStorage.fetchAll(AccountModel.self)
        XCTAssertEqual(saved.map(\.id), [existing.id])
    }

    func testImportGooglePlayWithMalformedKeyIsRejectedAndSavesNothing() async throws {
        let sut = makeGooglePlaySUT()
        let url = try makeImportFile(googlePlayPayload(serviceAccountJSON: #"{"type": "service_account""#))

        let error = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertEqual(
            error,
            String(localized: "The Google Play service account key in this file is invalid. Ask the sender to export the account again.")
        )
        let saved = try await mockStorage.fetchAll(AccountModel.self)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(mockKeychain.storedKeys.isEmpty)
    }

    func testGooglePlayListRejectsAppleFiles() async throws {
        let sut = makeGooglePlaySUT()
        let url = try makeImportFile([
            "name": "Team",
            "providerType": "apple",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "credentials": ["issuerID": "i", "privateKeyID": "k", "privateKey": "p"]
        ])

        let error = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertEqual(
            error,
            String(localized: "This file contains a \(ProviderType.apple.displayName) account, but this is the \(ProviderType.googlePlay.displayName) section.")
        )
        XCTAssertTrue(mockKeychain.storedKeys.isEmpty)
    }

    func testReimportGooglePlayReplacesTheExpiredAccountInPlace() async throws {
        let expired = AccountModel(
            name: "Expired",
            providerType: .googlePlay,
            origin: .imported,
            expirationDate: Date(timeIntervalSinceNow: -60)
        )
        try await mockStorage.save(expired, id: expired.id)
        mockKeychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(expired.id)"
        )
        let sut = makeGooglePlaySUT()
        sut.beginReimport(accountId: expired.id)
        let url = try makeImportFile(googlePlayPayload())

        let error = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertNil(error, "Re-importing the same service account is not a duplicate")
        XCTAssertNil(sut.uiState.replacingAccountId)
        XCTAssertEqual(sut.uiState.accounts.map(\.id), [expired.id])
        XCTAssertNil(sut.uiState.accounts.first?.expirationDate)
    }

    // MARK: - Apple import now honors the per-app scope

    func testImportAppleAccountParsesAppsBundles() async throws {
        let url = try makeImportFile([
            "name": "Team",
            "providerType": "apple",
            "createdAt": ISO8601DateFormatter().string(from: .now),
            "credentials": ["issuerID": "i", "privateKeyID": "k", "privateKey": "p"],
            "appsBundles": ["com.a"]
        ])

        let error = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertNil(error)
        XCTAssertEqual(sut.uiState.accounts.first?.appsBundles, ["com.a"])
    }

    // MARK: - Analytics events

    func testDeleteAccountTracksTapAndSuccess() async throws {
        let account = AccountModel(name: "ToDelete", providerType: .apple)
        try await mockStorage.save(account, id: account.id)

        await sut.deleteAccount(account)

        XCTAssertEqual(analytics.taps(of: .delete), [.buttonTap(.delete, on: .accountsList)])
        XCTAssertEqual(analytics.actions(of: .deleteAccount), [
            .action(.deleteAccount, on: .accountsList, result: .success, parameters: [
                AnalyticsParameterKey.kind: .string(ProviderType.apple.rawValue)
            ])
        ])
    }

    func testDeleteAccountTracksFailure() async throws {
        let account = AccountModel(name: "ToDelete", providerType: .apple)
        try await mockStorage.save(account, id: account.id)
        await mockStorage.failDelete(AccountModel.self, id: account.id)

        await sut.deleteAccount(account)

        XCTAssertEqual(analytics.results(of: .deleteAccount), [.failure])
    }

    func testImportTracksFailureForUnreadableFile() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).scexport")

        let error = await sut.importAccount(from: missing, password: "pw", customName: nil)

        XCTAssertNotNil(error)
        XCTAssertEqual(analytics.taps(of: .confirmImport), [.buttonTap(.confirmImport, on: .accountsListImport)])
        XCTAssertEqual(analytics.results(of: .importAccount), [.failure])
        XCTAssertEqual(
            analytics.actions(of: .importAccount).first?.parameters[AnalyticsParameterKey.errorCategory],
            .string("invalid_file")
        )
    }

    func testReimportTracksReimportAction() async {
        sut.beginReimport(accountId: "expired")
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).scexport")

        _ = await sut.importAccount(from: missing, password: "pw", customName: nil)

        XCTAssertEqual(analytics.results(of: .reimportAccount), [.failure])
        XCTAssertTrue(analytics.actions(of: .importAccount).isEmpty)
    }

    func testImportTracksSuccess() async throws {
        let password = "aVeryStrongPass123"
        let payload: [String: Any] = [
            "name": "Imported",
            "providerType": "apple",
            "credentials": ["issuerID": "issuer", "privateKeyID": "kid", "privateKey": "pk"]
        ]
        let json = try XCTUnwrap(String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).scexport")
        try AccountCrypto.encrypt(json: json, password: password).write(to: url)

        let error = await sut.importAccount(from: url, password: password, customName: nil)

        XCTAssertNil(error)
        XCTAssertEqual(analytics.results(of: .importAccount), [.success])
    }
}
