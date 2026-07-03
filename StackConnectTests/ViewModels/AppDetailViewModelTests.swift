import XCTest
@testable import StackConnect

@MainActor
final class AppDetailViewModelTests: XCTestCase {

    private var mockStorage: MockPersistentStorable!
    private var mockKeychain: MockKeyStorable!

    private let account = AccountModel(name: "Apple", providerType: .apple)
    private lazy var app = AppModel(
        id: "app-1",
        name: "StackConnect",
        bundleId: "com.stack.connect",
        accountId: account.id
    )

    override func setUp() async throws {
        try await super.setUp()
        mockStorage = MockPersistentStorable()
        mockKeychain = MockKeyStorable()
    }

    override func tearDown() async throws {
        mockStorage = nil
        mockKeychain = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT() -> AppDetailViewModel {
        AppDetailViewModel(
            app: app,
            account: account,
            storage: mockStorage,
            keychain: mockKeychain
        )
    }

    private func makeVersion(
        id: String,
        appStoreState: AppStoreState,
        versionString: String
    ) -> AppStoreVersionModel {
        AppStoreVersionModel(
            id: id,
            appStoreState: appStoreState,
            versionString: versionString,
            appId: app.id
        )
    }

    /// Seeds a cached version under `"version.{id}"`. The mock keys `fetchAll`
    /// by type only, so the id here just mirrors production.
    private func seed(version: AppStoreVersionModel) async throws {
        try await mockStorage.save(version, id: "version.\(version.id)")
    }

    /// Seeds a cached phased release under `"phased.{versionId}"` (production key).
    private func seed(phased: PhasedReleaseModel, forVersionId versionId: String) async throws {
        try await mockStorage.save(phased, id: "phased.\(versionId)")
    }

    // MARK: - Tests

    func testRefreshLoadsCachedActivePhasedReleaseForVersion() async throws {
        let version = makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "3.1.0")
        try await seed(version: version)
        try await seed(
            phased: PhasedReleaseModel(id: "phased.v1", state: .active, currentDayNumber: 3),
            forVersionId: "v1"
        )

        let sut = makeSUT()
        await sut.refresh()

        XCTAssertEqual(sut.uiState.phasedByVersionId["v1"]?.currentDayNumber, 3)
        XCTAssertEqual(sut.uiState.phasedByVersionId["v1"]?.state, .active)
    }

    func testRefreshWithoutPhasedEntryLeavesVersionUnmapped() async throws {
        let version = makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "3.1.0")
        try await seed(version: version)

        let sut = makeSUT()
        await sut.refresh()

        XCTAssertNil(sut.uiState.phasedByVersionId["v1"])
    }

    func testRefreshLoadsPausedPhasedReleaseForVersion() async throws {
        let version = makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "3.1.0")
        try await seed(version: version)
        try await seed(
            phased: PhasedReleaseModel(id: "phased.v1", state: .paused, currentDayNumber: 5),
            forVersionId: "v1"
        )

        let sut = makeSUT()
        await sut.refresh()

        XCTAssertEqual(sut.uiState.phasedByVersionId["v1"]?.state, .paused)
        XCTAssertEqual(sut.uiState.phasedByVersionId["v1"]?.currentDayNumber, 5)
    }
}
