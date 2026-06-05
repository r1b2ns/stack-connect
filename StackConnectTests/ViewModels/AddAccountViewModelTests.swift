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

    // Firebase used to be a no-op placeholder that saved with just a name ("skips validation").
    // It is now a real provider: saving requires a Service Account JSON. With no JSON provided,
    // save() must surface a validation error and persist nothing.
    func testSaveFirebaseAccountWithoutJSONShowsError() async {
        sut = AddAccountViewModel(
            providerType: .firebase,
            storage: mockStorage,
            keychain: mockKeychain
        )
        sut.uiState.accountName = "My Firebase"
        // No firebaseJSON set.

        await sut.save()

        XCTAssertNotNil(sut.uiState.validationError)
        XCTAssertFalse(sut.uiState.isSaved)

        let accounts: [AccountModel] = try! await mockStorage.fetchAll(AccountModel.self)
        XCTAssertTrue(accounts.isEmpty)
    }
}
