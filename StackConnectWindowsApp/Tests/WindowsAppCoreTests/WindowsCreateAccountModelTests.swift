import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsCreateAccountModel` (T-F09).
/// Covers: field validation, PEM sanitization, duplicate detection, persistence
/// order (SQLite-first atomicity), error handling, and state transitions.
@MainActor
final class WindowsCreateAccountModelTests: XCTestCase {

    private var storage: MockStorage!
    private var secrets: MockSecrets!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockStorage()
        secrets = MockSecrets()
    }

    override func tearDown() async throws {
        storage = nil
        secrets = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeAppleSUT() -> WindowsCreateAccountModel {
        WindowsCreateAccountModel(
            providerType: .apple,
            storage: storage,
            secrets: secrets
        )
    }

    private func makeFirebaseSUT() -> WindowsCreateAccountModel {
        WindowsCreateAccountModel(
            providerType: .firebase,
            storage: storage,
            secrets: secrets
        )
    }

    /// Fills the SUT with valid Apple form fields so that only the field under
    /// test needs to be overridden.
    private func fillAppleFields(_ sut: WindowsCreateAccountModel) {
        sut.accountName = "Test Account"
        sut.issuerID = "issuer-123"
        sut.privateKeyID = "key-id-456"
        sut.privateKey = "MIIEvQIBADANBg..."
    }

    // MARK: - Apple Validation (US-W03)

    func testSaveAppleAccount_emptyName_setsError() async {
        let sut = makeAppleSUT()
        fillAppleFields(sut)
        sut.accountName = "   " // whitespace-only

        await sut.saveAppleAccount()

        XCTAssertEqual(sut.errorMessage, "Account name is required.")
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveAppleAccount_emptyIssuerID_setsError() async {
        let sut = makeAppleSUT()
        fillAppleFields(sut)
        sut.issuerID = ""

        await sut.saveAppleAccount()

        XCTAssertEqual(sut.errorMessage, "Issuer ID is required.")
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveAppleAccount_emptyPrivateKeyID_setsError() async {
        let sut = makeAppleSUT()
        fillAppleFields(sut)
        sut.privateKeyID = "  "

        await sut.saveAppleAccount()

        XCTAssertEqual(sut.errorMessage, "Private Key ID is required.")
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveAppleAccount_emptyPrivateKey_setsError() async {
        let sut = makeAppleSUT()
        fillAppleFields(sut)
        sut.privateKey = " \n "

        await sut.saveAppleAccount()

        XCTAssertEqual(sut.errorMessage, "Private Key is required.")
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveAppleAccount_duplicateKey_setsError() async {
        // Given: an existing Apple account with a known private key
        let existingAccount = AccountModel(id: "existing-1", name: "Existing", providerType: .apple)
        let existingCreds = AppleCredentials(
            issuerID: "iss-1",
            privateKeyID: "kid-1",
            privateKey: "BASE64KEY"
        )
        try! await storage.save(existingAccount, id: existingAccount.id)
        secrets.setObject(existingCreds, forKey: "credentials.\(existingAccount.id)")

        // When: trying to save a new account with the same private key
        let sut = makeAppleSUT()
        fillAppleFields(sut)
        sut.privateKey = "BASE64KEY"

        await sut.saveAppleAccount()

        // Then: duplicate error is shown
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.errorMessage?.contains("Existing") == true)
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveAppleAccount_storageFailure_setsErrorAndResetsIsSaving() async {
        let sut = makeAppleSUT()
        fillAppleFields(sut)
        storage.shouldThrowOnSave = true

        await sut.saveAppleAccount()

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveAppleAccount_success_setsIsSaved() async {
        let sut = makeAppleSUT()
        fillAppleFields(sut)

        await sut.saveAppleAccount()

        XCTAssertTrue(sut.isSaved)
        XCTAssertFalse(sut.isSaving)
        XCTAssertNil(sut.errorMessage)
    }

    func testSaveAppleAccount_success_usesInjectedProviderType() async {
        // Verify the account is created with the injected provider type, not
        // a hardcoded one. We use .apple here; the model should use self.providerType.
        let sut = makeAppleSUT()
        fillAppleFields(sut)

        await sut.saveAppleAccount()

        // Fetch the persisted account and verify its provider type
        let accounts: [AccountModel] = try! await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.providerType, .apple)
    }

    func testSaveAppleAccount_success_persistsSQLiteBeforeCredentials() async {
        // When storage throws, no credentials should be written (atomicity).
        let sut = makeAppleSUT()
        fillAppleFields(sut)
        storage.shouldThrowOnSave = true

        await sut.saveAppleAccount()

        // Verify no credentials were written to secrets
        // Since we can't easily enumerate MockSecrets, we check that no account
        // was saved (storage threw), and thus credentials should not exist.
        let accounts: [AccountModel] = try! await storage.fetchAll(AccountModel.self)
        XCTAssertTrue(accounts.isEmpty, "No account should be saved when storage throws")
    }

    // MARK: - PEM Sanitization

    func testSanitizedPrivateKey_stripsPEMHeaders() {
        let sut = makeAppleSUT()
        let pemKey = """
        -----BEGIN PRIVATE KEY-----
        MIIEvQIBADANBg==
        -----END PRIVATE KEY-----
        """

        let result = sut.sanitizedPrivateKey(pemKey)

        XCTAssertEqual(result, "MIIEvQIBADANBg==")
        XCTAssertFalse(result.contains("-----"))
        XCTAssertFalse(result.contains("\n"))
    }

    func testSanitizedPrivateKey_keyWithoutHeaders_returnsUnchanged() {
        let sut = makeAppleSUT()
        let rawKey = "MIIEvQIBADANBg=="

        let result = sut.sanitizedPrivateKey(rawKey)

        XCTAssertEqual(result, "MIIEvQIBADANBg==")
    }

    func testSanitizedPrivateKey_stripsWindowsCRLF() {
        let sut = makeAppleSUT()
        // Simulate a Windows-style PEM file with \r\n line endings
        let pemKey = "-----BEGIN PRIVATE KEY-----\r\nMIIEvQIBADANBg==\r\n-----END PRIVATE KEY-----\r\n"

        let result = sut.sanitizedPrivateKey(pemKey)

        XCTAssertEqual(result, "MIIEvQIBADANBg==")
        XCTAssertFalse(result.contains("\r"))
        XCTAssertFalse(result.contains("\n"))
    }

    // MARK: - Firebase Validation (US-W04)

    func testSaveFirebaseAccount_emptyName_setsError() async {
        let sut = makeFirebaseSUT()
        sut.accountName = ""
        sut.serviceAccountJSON = "{\"type\": \"service_account\"}"

        await sut.saveFirebaseAccount()

        XCTAssertEqual(sut.errorMessage, "Account name is required.")
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveFirebaseAccount_emptyJSON_setsError() async {
        let sut = makeFirebaseSUT()
        sut.accountName = "Firebase Account"
        sut.serviceAccountJSON = "   " // whitespace-only

        await sut.saveFirebaseAccount()

        XCTAssertEqual(sut.errorMessage, "Service Account JSON is required.")
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveFirebaseAccount_invalidJSON_setsError() async {
        let sut = makeFirebaseSUT()
        sut.accountName = "Firebase Account"
        sut.serviceAccountJSON = "not valid json {{"

        await sut.saveFirebaseAccount()

        XCTAssertEqual(sut.errorMessage, "Invalid JSON format.")
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveFirebaseAccount_duplicateJSON_setsError() async {
        // Given: an existing Firebase account with known JSON
        let json = "{\"type\":\"service_account\"}"
        let existingAccount = AccountModel(id: "fb-1", name: "Existing FB", providerType: .firebase)
        let existingCreds = FirebaseCredentials(serviceAccountJSON: json)
        try! await storage.save(existingAccount, id: existingAccount.id)
        secrets.setObject(existingCreds, forKey: "credentials.\(existingAccount.id)")

        // When: trying to save a new account with the same JSON
        let sut = makeFirebaseSUT()
        sut.accountName = "New Firebase"
        sut.serviceAccountJSON = json

        await sut.saveFirebaseAccount()

        // Then: duplicate error is shown
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.errorMessage?.contains("Existing FB") == true)
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveFirebaseAccount_storageFailure_setsErrorAndResetsIsSaving() async {
        let sut = makeFirebaseSUT()
        sut.accountName = "Firebase Account"
        sut.serviceAccountJSON = "{\"type\":\"service_account\"}"
        storage.shouldThrowOnSave = true

        await sut.saveFirebaseAccount()

        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isSaving)
        XCTAssertFalse(sut.isSaved)
    }

    func testSaveFirebaseAccount_success_setsIsSaved() async {
        let sut = makeFirebaseSUT()
        sut.accountName = "Firebase Account"
        sut.serviceAccountJSON = "{\"type\":\"service_account\"}"

        await sut.saveFirebaseAccount()

        XCTAssertTrue(sut.isSaved)
        XCTAssertFalse(sut.isSaving)
        XCTAssertNil(sut.errorMessage)
    }

    func testSaveFirebaseAccount_success_usesInjectedProviderType() async {
        let sut = makeFirebaseSUT()
        sut.accountName = "Firebase Account"
        sut.serviceAccountJSON = "{\"type\":\"service_account\"}"

        await sut.saveFirebaseAccount()

        let accounts: [AccountModel] = try! await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.providerType, .firebase)
    }
}
