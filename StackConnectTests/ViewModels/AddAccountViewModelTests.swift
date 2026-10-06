import XCTest
import StackCoreRust
@testable import StackConnect

@MainActor
final class AddAccountViewModelTests: XCTestCase {

    private var sut: AddAccountViewModel!
    private var mockStorage: MockPersistentStorable!
    private var mockKeychain: MockKeyStorable!

    override func setUp() async throws {
        try await super.setUp()
        mockStorage = MockPersistentStorable()
        mockKeychain = MockKeyStorable()
    }

    override func tearDown() async throws {
        sut = nil
        mockStorage = nil
        mockKeychain = nil
        try await super.tearDown()
    }

    // MARK: - Validation

    func testSaveWithEmptyNameShowsError() async {
        sut = AddAccountViewModel(
            providerType: .apple,
            storage: mockStorage,
            keychain: mockKeychain
        )
        sut.uiState.accountName = "   "

        await sut.save()

        XCTAssertNotNil(sut.uiState.validationError)
        XCTAssertFalse(sut.uiState.isSaved)
    }

    // Firebase save is NOT a no-op: it requires a non-empty Service Account JSON and
    // then performs a live `APIProviderFirebase.request(...)` network validation, which
    // (like the Apple `validateCredentials()` call) has no injection seam to stub
    // offline. We therefore assert the JSON-required guard that runs before any network
    // call: a valid name but no JSON must surface the "Service Account JSON is required."
    // error and persist nothing.
    func testSaveFirebaseAccountWithoutJSONShowsError() async {
        sut = AddAccountViewModel(
            providerType: .firebase,
            storage: mockStorage,
            keychain: mockKeychain
        )
        sut.uiState.accountName = "My Firebase"   // valid name, but no Service Account JSON

        await sut.save()

        XCTAssertEqual(
            sut.uiState.validationError,
            String(localized: "Service Account JSON is required.")
        )
        XCTAssertFalse(sut.uiState.isSaved)

        let accounts: [AccountModel] = try! await mockStorage.fetchAll(AccountModel.self)
        XCTAssertTrue(accounts.isEmpty)
    }

    // MARK: - Apple Duplicate Relaxation (issue #66)
    //
    // NOTE on the network seam: `AddAccountViewModel.save()` instantiates
    // `AppleAccountConnection` directly and there is no injection point to stub
    // `validateCredentials()`, which performs a live ASC request. The duplicate
    // check, however, runs BEFORE that network call and returns early, so we
    // assert the relaxed logic at that seam:
    //   - Same key + same name  → blocked with the specific duplicate message
    //     (returns before any network call).
    //   - Same key + diff name  → NOT blocked; `save()` proceeds to network
    //     validation (which fails offline), so we only assert that the failure
    //     is NOT the duplicate message.

    private let duplicateError = String(
        localized: "An account with these credentials already exists: \"Existing\"."
    )

    /// Stores an existing Apple account named "Existing" with the given private key.
    private func seedExistingAppleAccount(privateKey: String) async throws {
        let existing = AccountModel(name: "Existing", providerType: .apple)
        try await mockStorage.save(existing, id: existing.id)
        mockKeychain.setObject(
            AppleCredentials(issuerID: "issuer-1", privateKeyID: "kid-1", privateKey: privateKey),
            forKey: "credentials.\(existing.id)"
        )
    }

    func testSaveAppleSameKeySameNameIsBlocked() async throws {
        let key = "PRIVATE-KEY-ABC"
        try await seedExistingAppleAccount(privateKey: key)

        sut = AddAccountViewModel(
            providerType: .apple,
            storage: mockStorage,
            keychain: mockKeychain
        )
        sut.uiState.accountName = "Existing"        // same name
        sut.uiState.issuerID = "issuer-1"
        sut.uiState.privateKeyID = "kid-1"
        sut.uiState.privateKey = key                // same key

        await sut.save()

        // Blocked at the duplicate check, before any network validation.
        XCTAssertEqual(sut.uiState.validationError, duplicateError)
        XCTAssertFalse(sut.uiState.isSaved)

        let accounts: [AccountModel] = try await mockStorage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts.count, 1) // nothing new persisted
    }

    func testSaveAppleSameKeyDifferentNameIsNotBlockedByDuplicateCheck() async throws {
        let key = "PRIVATE-KEY-ABC"
        try await seedExistingAppleAccount(privateKey: key)

        sut = AddAccountViewModel(
            providerType: .apple,
            storage: mockStorage,
            keychain: mockKeychain
        )
        sut.uiState.accountName = "Different Role" // different name
        sut.uiState.issuerID = "issuer-1"
        sut.uiState.privateKeyID = "kid-1"
        sut.uiState.privateKey = key               // same key

        await sut.save()

        // The duplicate check must NOT block this. save() then proceeds to live
        // network validation, which fails offline — so we only assert the error
        // is not the duplicate message (and the account was not saved as a dup).
        XCTAssertNotEqual(sut.uiState.validationError, duplicateError)
        XCTAssertFalse(sut.uiState.isSaved) // didn't save (network validation failed), but NOT for duplication
    }

    // MARK: - Google Play
    //
    // The live check (token exchange + Play Developer Reporting API through the
    // Rust core) sits behind `googlePlayConnectionFactory`, so these tests inject
    // `MockGooglePlayAccountConnection` and never touch the network.

    private func makeGooglePlaySUT(connection: MockGooglePlayAccountConnection) -> AddAccountViewModel {
        AddAccountViewModel(
            providerType: .googlePlay,
            storage: mockStorage,
            keychain: mockKeychain,
            googlePlayConnectionFactory: connection.factory
        )
    }

    private func storedAccounts() async throws -> [AccountModel] {
        try await mockStorage.fetchAll(AccountModel.self)
    }

    func testSaveGooglePlayWithEmptyJSONShowsRequiredErrorAndSkipsValidation() async throws {
        let connection = MockGooglePlayAccountConnection()
        sut = makeGooglePlaySUT(connection: connection)
        sut.uiState.accountName = "My Play"
        sut.uiState.googlePlayJSON = "  \n "

        await sut.save()

        XCTAssertEqual(sut.uiState.validationError, String(localized: "Service Account JSON is required."))
        XCTAssertFalse(sut.uiState.isSaved)
        XCTAssertFalse(sut.uiState.isValidating)
        XCTAssertEqual(connection.validateCallCount, 0)
        let accounts = try await storedAccounts()
        XCTAssertTrue(accounts.isEmpty)
    }

    func testSaveGooglePlayWithMalformedJSONShowsParseErrorAndSkipsValidation() async throws {
        let connection = MockGooglePlayAccountConnection()
        sut = makeGooglePlaySUT(connection: connection)
        sut.uiState.accountName = "My Play"
        sut.uiState.googlePlayJSON = #"{"type": "service_account", "client_email": "#

        await sut.save()

        XCTAssertEqual(
            sut.uiState.validationError,
            GooglePlayServiceAccount.ParseError.malformedJSON.localizedDescription
        )
        XCTAssertFalse(sut.uiState.isSaved)
        XCTAssertEqual(connection.validateCallCount, 0)
        let accounts = try await storedAccounts()
        XCTAssertTrue(accounts.isEmpty)
    }

    func testSaveGooglePlayWithSameClientEmailIsBlockedAsDuplicate() async throws {
        // Existing account stored with a compact JSON of the same service account.
        let existing = AccountModel(name: "Existing", providerType: .googlePlay)
        try await mockStorage.save(existing, id: existing.id)
        let storedJSON = #"{"type":"service_account","client_email":"STACK-CONNECT@my-project.iam.gserviceaccount.com","private_key_id":"old-key","private_key":"-----BEGIN PRIVATE KEY-----\nA\n-----END PRIVATE KEY-----\n"}"#
        mockKeychain.setObject(GooglePlayCredentials(serviceAccountJSON: storedJSON), forKey: "credentials.\(existing.id)")

        let connection = MockGooglePlayAccountConnection()
        sut = makeGooglePlaySUT(connection: connection)
        sut.uiState.accountName = "Another name"
        // Re-downloaded key (new key id, pretty-printed) of the same service account.
        sut.uiState.googlePlayJSON = GooglePlayTestFixtures.serviceAccountJSON(privateKeyId: "new-key")

        await sut.save()

        XCTAssertEqual(sut.uiState.validationError, duplicateError)
        XCTAssertFalse(sut.uiState.isSaved)
        XCTAssertEqual(connection.validateCallCount, 0, "Duplicates are rejected before the network check")
        let accounts = try await storedAccounts()
        XCTAssertEqual(accounts.count, 1)
    }

    func testSaveGooglePlayValidationFailureShowsTranslatedMessageAndSavesNothing() async throws {
        let detail = "The service account is not invited in Play Console. Invite it under Users and permissions."
        let connection = MockGooglePlayAccountConnection()
        connection.validateHandler = { throw StackError.Auth(message: detail) }
        sut = makeGooglePlaySUT(connection: connection)
        sut.uiState.accountName = "My Play"
        sut.uiState.googlePlayJSON = GooglePlayTestFixtures.serviceAccountJSON()

        await sut.save()

        XCTAssertEqual(
            sut.uiState.validationError,
            GooglePlayErrorTranslator.friendlyMessage(for: StackError.Auth(message: detail))
        )
        XCTAssertTrue(sut.uiState.validationError?.contains(detail) == true)
        XCTAssertFalse(sut.uiState.isSaved)
        XCTAssertFalse(sut.uiState.isValidating)
        XCTAssertEqual(connection.validateCallCount, 1)
        let accounts = try await storedAccounts()
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertTrue(mockKeychain.storedKeys.isEmpty, "No credentials may be stored when validation fails")
    }

    func testSaveGooglePlaySuccessSavesAccountAndKeychainEntry() async throws {
        // Another service account already exists: not a duplicate.
        let other = AccountModel(name: "Other", providerType: .googlePlay)
        try await mockStorage.save(other, id: other.id)
        mockKeychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON(clientEmail: "other@proj.iam.gserviceaccount.com")),
            forKey: "credentials.\(other.id)"
        )

        let connection = MockGooglePlayAccountConnection()
        sut = makeGooglePlaySUT(connection: connection)
        let json = GooglePlayTestFixtures.serviceAccountJSON()
        sut.uiState.accountName = "  My Play  "
        sut.uiState.role = .developer // Picker hidden for Google Play: ignored.
        sut.uiState.googlePlayJSON = "\n" + json + "\n"

        await sut.save()

        XCTAssertNil(sut.uiState.validationError)
        XCTAssertTrue(sut.uiState.isSaved)
        XCTAssertEqual(connection.validateCallCount, 1)
        XCTAssertEqual(connection.credentials.map(\.serviceAccountJSON), [json])

        let accounts = try await storedAccounts()
        let created = try XCTUnwrap(accounts.first { $0.id != other.id })
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(created.name, "My Play")
        XCTAssertEqual(created.providerType, .googlePlay)
        XCTAssertEqual(created.role, .unspecified, "Google Play accounts keep the default role")

        // Storage format unchanged (plan D2): the whole trimmed JSON file.
        let saved: GooglePlayCredentials? = mockKeychain.object(forKey: "credentials.\(created.id)")
        XCTAssertEqual(saved?.serviceAccountJSON, json)
    }
}
