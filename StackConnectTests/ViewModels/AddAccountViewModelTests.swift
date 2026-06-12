import XCTest
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

    func testSaveFirebaseAccountSkipsValidation() async {
        sut = AddAccountViewModel(
            providerType: .firebase,
            storage: mockStorage,
            keychain: mockKeychain
        )
        sut.uiState.accountName = "My Firebase"

        await sut.save()

        XCTAssertTrue(sut.uiState.isSaved)

        let accounts: [AccountModel] = try! await mockStorage.fetchAll(AccountModel.self)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.name, "My Firebase")
        XCTAssertEqual(accounts.first?.providerType, .firebase)
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
}
