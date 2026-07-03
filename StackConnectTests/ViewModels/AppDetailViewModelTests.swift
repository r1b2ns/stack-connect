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

    // MARK: - Suggested next version

    func testSuggestedNextVersionBumpsMinorAndResetsPatch() {
        let versions = [makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "3.1.0")]
        XCTAssertEqual(AppDetailViewModel.suggestedNextVersion(from: versions), "3.2.0")
    }

    func testSuggestedNextVersionResetsPatchFromNonZero() {
        let versions = [makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "3.1.4")]
        XCTAssertEqual(AppDetailViewModel.suggestedNextVersion(from: versions), "3.2.0")
    }

    func testSuggestedNextVersionPicksHighestAcrossVersions() {
        let versions = [
            makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "1.0.0"),
            makeVersion(id: "v2", appStoreState: .prepareForSubmission, versionString: "3.1.0"),
            makeVersion(id: "v3", appStoreState: .readyForSale, versionString: "2.5.9")
        ]
        XCTAssertEqual(AppDetailViewModel.suggestedNextVersion(from: versions), "3.2.0")
    }

    func testSuggestedNextVersionComparesSemanticallyNotLexically() {
        let versions = [
            makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "3.9.0"),
            makeVersion(id: "v2", appStoreState: .readyForSale, versionString: "3.10.0")
        ]
        // 3.10.0 is the highest (not 3.9.0 from string sorting) → 3.11.0.
        XCTAssertEqual(AppDetailViewModel.suggestedNextVersion(from: versions), "3.11.0")
    }

    func testSuggestedNextVersionHandlesTwoComponents() {
        let versions = [makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "3.1")]
        XCTAssertEqual(AppDetailViewModel.suggestedNextVersion(from: versions), "3.2.0")
    }

    func testSuggestedNextVersionFallsBackWhenNoParseableVersions() {
        XCTAssertEqual(AppDetailViewModel.suggestedNextVersion(from: []), "1.0.0")
        let junk = [makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "beta")]
        XCTAssertEqual(AppDetailViewModel.suggestedNextVersion(from: junk), "1.0.0")
    }

    @MainActor
    func testPrepareCreatePlatformSetsSuggestionAndOpensSheet() {
        let sut = makeSUT()
        sut.uiState.versions = [makeVersion(id: "v1", appStoreState: .readyForSale, versionString: "3.1.0")]

        sut.prepareCreatePlatform()

        XCTAssertEqual(sut.uiState.newVersionString, "3.2.0")
        XCTAssertTrue(sut.uiState.showCreatePlatform)
        XCTAssertTrue(sut.uiState.selectedPlatforms.isEmpty)
    }
}
