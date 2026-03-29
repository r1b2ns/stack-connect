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
}
