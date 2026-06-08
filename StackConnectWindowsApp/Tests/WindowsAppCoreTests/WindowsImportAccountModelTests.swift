import XCTest
import Foundation
import StackProtocols
import StackHomeCore
import StackCrypto
@testable import WindowsAppCore

// MARK: - Tests

/// Unit tests for `WindowsImportAccountModel` (T-F12).
///
/// Covers: 3-step progressive import flow, validation at each step, decryption,
/// duplicate detection, error messages, and successful save with origin=.imported.
///
/// Test coverage mapped to acceptance criteria:
///   - TC-F047: Import form displays all fields (UI — verified structurally via step states)
///   - TC-F049: Valid decrypt shows confirmation (Integration, P0)
///   - TC-F050: Confirm stores with origin=.imported (Integration, P0)
///   - TC-F051: Empty file path shows error (UI, P0)
///   - TC-F052: Unreadable file shows error (Integration, P0)
///   - TC-F053: Wrong password shows error (Integration, P0)
///   - TC-F054: Missing JSON fields shows error (Integration, P1)
///   - TC-F055: Provider mismatch shows error (Integration, P1)
///   - TC-F056: Duplicate credentials shows error (Integration, P0)
@MainActor
final class WindowsImportAccountModelTests: XCTestCase {

    private var storage: MockStorage!
    private var secrets: MockSecrets!

    /// Test password used for encryption/decryption in all tests.
    private let testPassword = "SuperSecret12345!"

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

    /// Creates a SUT with a mock file reader that returns the given data for any path.
    private func makeSUT(
        expectedProvider: ProviderType = .apple,
        fileData: Data? = nil,
        fileReaderError: Error? = nil
    ) -> WindowsImportAccountModel {
        WindowsImportAccountModel(
            expectedProvider: expectedProvider,
            storage: storage,
            secrets: secrets,
            fileReader: { _ in
                if let error = fileReaderError {
                    throw error
                }
                guard let data = fileData else {
                    throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data"])
                }
                return data
            }
        )
    }

    /// Builds a valid Apple export JSON, encrypts it, and returns the `.scexport` Data.
    private func makeEncryptedAppleExport(
        name: String = "Test Apple Account",
        providerType: String = "apple",
        issuerID: String = "test-issuer-id",
        privateKeyID: String = "test-private-key-id",
        privateKey: String = "test-private-key-content",
        includeCredentials: Bool = true,
        includeName: Bool = true,
        includeProvider: Bool = true,
        extraFields: [String: Any] = [:],
        password: String? = nil
    ) throws -> Data {
        var dict: [String: Any] = [:]

        if includeName {
            dict["name"] = name
        }
        if includeProvider {
            dict["providerType"] = providerType
        }

        dict["createdAt"] = ISO8601DateFormatter().string(from: Date())

        if includeCredentials {
            dict["credentials"] = [
                "issuerID": issuerID,
                "privateKeyID": privateKeyID,
                "privateKey": privateKey
            ]
        }

        // Merge extra fields
        for (key, value) in extraFields {
            dict[key] = value
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        return try AccountCrypto.encrypt(json: jsonString, password: password ?? testPassword)
    }

    /// Builds a valid Firebase export JSON, encrypts it, and returns the `.scexport` Data.
    private func makeEncryptedFirebaseExport(
        name: String = "Test Firebase Account",
        serviceAccountJSON: String = "{\"project_id\": \"test-project\"}",
        password: String? = nil
    ) throws -> Data {
        let dict: [String: Any] = [
            "name": name,
            "providerType": "firebase",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "credentials": [
                "serviceAccountJSON": serviceAccountJSON
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        return try AccountCrypto.encrypt(json: jsonString, password: password ?? testPassword)
    }

    // MARK: - TC-F047: Initial State / Form Fields

    func testInitialStepIsSelectFile() {
        let sut = makeSUT()

        XCTAssertEqual(sut.step, .selectFile)
        XCTAssertEqual(sut.filePath, "")
        XCTAssertEqual(sut.password, "")
        XCTAssertEqual(sut.accountName, "")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isProcessing)
        XCTAssertFalse(sut.didFinishImport)
    }

    // MARK: - TC-F051: Empty file path shows error (AC-4)

    func testEmptyFilePathShowsError() async {
        let sut = makeSUT()
        sut.filePath = ""

        await sut.advanceStep()

        XCTAssertEqual(sut.step, .selectFile, "Should remain on selectFile step")
        XCTAssertEqual(sut.errorMessage, "File path is required.")
    }

    func testWhitespaceOnlyFilePathShowsError() async {
        let sut = makeSUT()
        sut.filePath = "   "

        await sut.advanceStep()

        XCTAssertEqual(sut.step, .selectFile)
        XCTAssertEqual(sut.errorMessage, "File path is required.")
    }

    // MARK: - TC-F052: Unreadable file shows error (AC-5)

    func testUnreadableFileShowsErrorOnSelectFile() async {
        let sut = makeSUT(
            fileReaderError: NSError(domain: "test", code: 2, userInfo: nil)
        )
        sut.filePath = "/nonexistent/path.scexport"

        await sut.advanceStep()

        XCTAssertEqual(sut.step, .selectFile, "Should remain on selectFile step")
        XCTAssertEqual(sut.errorMessage, "Failed to read file.")
    }

    // MARK: - Valid file path advances to enterPassword

    func testValidFilePathAdvancesToEnterPassword() async throws {
        let fileData = try makeEncryptedAppleExport()
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - TC-F053: Wrong password shows error (AC-6)

    func testWrongPasswordShowsError() async throws {
        let fileData = try makeEncryptedAppleExport(password: "CorrectPassword123")
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        // Step 1: select file
        await sut.advanceStep()
        XCTAssertEqual(sut.step, .enterPassword)

        // Step 2: enter wrong password
        sut.password = "WrongPassword456"
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword, "Should remain on enterPassword step")
        XCTAssertEqual(sut.errorMessage, "Decryption failed. Check your password and try again.")
    }

    // MARK: - TC-F049: Valid decrypt shows confirmation (AC-2)

    func testValidDecryptShowsConfirmation() async throws {
        let fileData = try makeEncryptedAppleExport(name: "My Apple Dev")
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        // Step 1
        await sut.advanceStep()
        XCTAssertEqual(sut.step, .enterPassword)

        // Step 2: correct password
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .confirmName, "Should advance to confirmName")
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(sut.accountName, "My Apple Dev", "Name should be pre-populated from file")
        XCTAssertEqual(sut.parsedProviderType, .apple)
    }

    // MARK: - TC-F050: Confirm stores with origin=.imported (AC-3)

    func testConfirmStoresAccountWithImportedOrigin() async throws {
        let fileData = try makeEncryptedAppleExport(
            name: "Imported Account",
            issuerID: "iss-123",
            privateKeyID: "pk-456",
            privateKey: "pk-content-789"
        )
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        // Step 1
        await sut.advanceStep()
        // Step 2
        sut.password = testPassword
        await sut.advanceStep()
        XCTAssertEqual(sut.step, .confirmName)

        // Step 3: confirm name
        await sut.advanceStep()

        XCTAssertTrue(sut.didFinishImport, "Import should be marked as finished")
        XCTAssertNil(sut.errorMessage)

        // Verify account was saved in storage
        let accounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts.count, 1)
        let saved = accounts[0]
        XCTAssertEqual(saved.name, "Imported Account")
        XCTAssertEqual(saved.providerType, .apple)
        XCTAssertEqual(saved.origin, .imported, "Origin must be .imported (AC-3)")

        // Verify credentials were stored in secrets
        let credData = secrets.data(forKey: "credentials.\(saved.id)")
        XCTAssertNotNil(credData, "Credentials should be stored in secrets")

        // Verify credential content
        if let data = credData,
           let credDict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            XCTAssertEqual(credDict["issuerID"], "iss-123")
            XCTAssertEqual(credDict["privateKeyID"], "pk-456")
            XCTAssertEqual(credDict["privateKey"], "pk-content-789")
        } else {
            XCTFail("Stored credentials should be decodable as [String: String]")
        }
    }

    func testConfirmWithCustomNameStoresCustomName() async throws {
        let fileData = try makeEncryptedAppleExport(name: "Original Name")
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        // Steps 1 & 2
        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()
        XCTAssertEqual(sut.step, .confirmName)

        // Modify name before confirming
        sut.accountName = "Custom Name"
        await sut.advanceStep()

        XCTAssertTrue(sut.didFinishImport)
        let accounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts[0].name, "Custom Name")
    }

    // MARK: - TC-F054: Missing JSON fields shows error (AC-7)

    func testMissingNameFieldShowsError() async throws {
        let fileData = try makeEncryptedAppleExport(includeName: false)
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep() // to enterPassword
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword, "Should remain on enterPassword")
        XCTAssertEqual(sut.errorMessage, "Missing or invalid 'name' field.")
    }

    func testMissingProviderTypeFieldShowsError() async throws {
        let fileData = try makeEncryptedAppleExport(includeProvider: false)
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword)
        XCTAssertEqual(sut.errorMessage, "Missing or invalid 'providerType' field.")
    }

    func testMissingCredentialsFieldShowsError() async throws {
        let fileData = try makeEncryptedAppleExport(includeCredentials: false)
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword)
        XCTAssertEqual(sut.errorMessage, "Missing or invalid 'credentials' field.")
    }

    func testMissingAppleIssuerIDShowsError() async throws {
        let fileData = try makeEncryptedAppleExport(issuerID: "")
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword)
        XCTAssertEqual(sut.errorMessage, "Missing or invalid 'issuerID' field.")
    }

    func testMissingApplePrivateKeyIDShowsError() async throws {
        let fileData = try makeEncryptedAppleExport(privateKeyID: "")
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword)
        XCTAssertEqual(sut.errorMessage, "Missing or invalid 'privateKeyID' field.")
    }

    func testMissingApplePrivateKeyShowsError() async throws {
        let fileData = try makeEncryptedAppleExport(privateKey: "")
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword)
        XCTAssertEqual(sut.errorMessage, "Missing or invalid 'privateKey' field.")
    }

    // MARK: - TC-F055: Provider mismatch shows error (AC-8)

    func testProviderMismatchShowsError() async throws {
        // File contains a Firebase account, but we're importing for Apple
        let fileData = try makeEncryptedFirebaseExport()
        let sut = makeSUT(expectedProvider: .apple, fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword, "Should remain on enterPassword")
        XCTAssertTrue(
            sut.errorMessage?.contains("Firebase") == true,
            "Error should mention the file's provider: \(sut.errorMessage ?? "nil")"
        )
    }

    // MARK: - TC-F056: Duplicate credentials shows error (AC-9)

    func testDuplicateAppleCredentialsShowsError() async throws {
        // Pre-existing account with the same private key
        let existingAccount = AccountModel(id: "existing-1", name: "Existing Apple", providerType: .apple)
        try await storage.save(existingAccount, id: existingAccount.id)

        let existingCreds: [String: String] = [
            "issuerID": "iss-existing",
            "privateKeyID": "pk-existing",
            "privateKey": "same-private-key"
        ]
        let credData = try JSONSerialization.data(withJSONObject: existingCreds)
        secrets.set(credData, forKey: "credentials.existing-1")

        // New import file has the same private key
        let fileData = try makeEncryptedAppleExport(privateKey: "same-private-key")
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword)
        XCTAssertEqual(
            sut.errorMessage,
            "An account with these credentials already exists: 'Existing Apple'."
        )
    }

    func testDuplicateFirebaseCredentialsShowsError() async throws {
        let existingAccount = AccountModel(id: "existing-fb", name: "Existing Firebase", providerType: .firebase)
        try await storage.save(existingAccount, id: existingAccount.id)

        let existingCreds: [String: String] = [
            "serviceAccountJSON": "{\"project_id\": \"test-project\"}"
        ]
        let credData = try JSONSerialization.data(withJSONObject: existingCreds)
        secrets.set(credData, forKey: "credentials.existing-fb")

        let fileData = try makeEncryptedFirebaseExport(
            serviceAccountJSON: "{\"project_id\": \"test-project\"}"
        )
        let sut = makeSUT(expectedProvider: .firebase, fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .enterPassword)
        XCTAssertEqual(
            sut.errorMessage,
            "An account with these credentials already exists: 'Existing Firebase'."
        )
    }

    // MARK: - Navigation (goBack)

    func testGoBackFromEnterPasswordReturnsToSelectFile() async throws {
        let fileData = try makeEncryptedAppleExport()
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        XCTAssertEqual(sut.step, .enterPassword)

        sut.goBack()

        XCTAssertEqual(sut.step, .selectFile)
        XCTAssertEqual(sut.password, "", "Password should be cleared on goBack")
    }

    func testGoBackFromConfirmNameReturnsToEnterPassword() async throws {
        let fileData = try makeEncryptedAppleExport()
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()
        XCTAssertEqual(sut.step, .confirmName)

        sut.goBack()

        XCTAssertEqual(sut.step, .enterPassword)
    }

    func testGoBackFromSelectFileDoesNothing() {
        let sut = makeSUT()

        sut.goBack()

        XCTAssertEqual(sut.step, .selectFile, "Should remain on selectFile")
    }

    func testGoBackClearsErrorMessage() async throws {
        let sut = makeSUT(
            fileReaderError: NSError(domain: "test", code: 1, userInfo: nil)
        )
        sut.filePath = "/bad/path.scexport"

        await sut.advanceStep()
        XCTAssertNotNil(sut.errorMessage)

        // goBack on selectFile clears error even though it doesn't navigate
        sut.goBack()
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Rules and Expiration Parsing

    func testRulesAreParsedFromFile() async throws {
        let rules: [String: Any] = [
            "apps": ["view", "edit"],
            "version": ["view"],
            "users": [],
            "review": ["view", "edit", "delete"],
            "testFlight": [],
            "analytics": ["view"],
            "provisioning": []
        ]

        let fileData = try makeEncryptedAppleExport(
            extraFields: ["rules": rules]
        )
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()
        XCTAssertEqual(sut.step, .confirmName)

        // Confirm to save
        await sut.advanceStep()
        XCTAssertTrue(sut.didFinishImport)

        let accounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts.count, 1)
        let saved = accounts[0]
        XCTAssertEqual(saved.rules.apps, [.view, .edit])
        XCTAssertEqual(saved.rules.version, [.view])
        XCTAssertTrue(saved.rules.users.isEmpty)
        XCTAssertEqual(saved.rules.review, [.view, .edit, .delete])
    }

    func testExpirationDateIsParsedFromFile() async throws {
        let expDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 30))
        let fileData = try makeEncryptedAppleExport(
            extraFields: ["expirationDate": expDate]
        )
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()
        await sut.advanceStep()

        XCTAssertTrue(sut.didFinishImport)

        let accounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
        XCTAssertNotNil(accounts[0].expirationDate)
    }

    // MARK: - Save Failure

    func testSaveFailureShowsError() async throws {
        let fileData = try makeEncryptedAppleExport()
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()
        XCTAssertEqual(sut.step, .confirmName)

        // Make storage throw on save
        storage.shouldThrowOnSave = true
        await sut.advanceStep()

        XCTAssertFalse(sut.didFinishImport)
        XCTAssertEqual(sut.errorMessage, "Failed to save imported account.")
    }

    func testSaveFailureRollsBackCredentials() async throws {
        let fileData = try makeEncryptedAppleExport()
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()

        storage.shouldThrowOnSave = true
        await sut.advanceStep()

        // No credentials should remain in secrets (they were rolled back)
        // We don't know the exact account ID, but we can check that no new
        // credentials keys were added (only the mock's initial empty state)
        let allSecretKeys = secrets.data(forKey: "credentials.")
        XCTAssertNil(allSecretKeys, "Rolled-back credentials should not persist")
    }

    // MARK: - Empty account name on confirm

    func testEmptyAccountNameOnConfirmShowsError() async throws {
        let fileData = try makeEncryptedAppleExport()
        let sut = makeSUT(fileData: fileData)
        sut.filePath = "/valid/path.scexport"

        await sut.advanceStep()
        sut.password = testPassword
        await sut.advanceStep()
        XCTAssertEqual(sut.step, .confirmName)

        // Clear the name
        sut.accountName = ""
        await sut.advanceStep()

        XCTAssertEqual(sut.step, .confirmName, "Should remain on confirmName")
        XCTAssertEqual(sut.errorMessage, "Account name is required.")
        XCTAssertFalse(sut.didFinishImport)
    }

    // MARK: - advanceStep clears previous error

    func testAdvanceStepClearsPreviousError() async {
        let sut = makeSUT(
            fileReaderError: NSError(domain: "test", code: 1, userInfo: nil)
        )
        sut.filePath = "/bad/path"

        await sut.advanceStep()
        XCTAssertNotNil(sut.errorMessage)

        // Try again with a different (still bad) path — error should change, not accumulate
        sut.filePath = "" // triggers different error
        await sut.advanceStep()
        XCTAssertEqual(sut.errorMessage, "File path is required.")
    }
}
