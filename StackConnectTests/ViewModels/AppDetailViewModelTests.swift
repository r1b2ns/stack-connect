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

    private func makeBuild(
        id: String,
        uploadedDate: Date?,
        iconUrl: String?,
        platform: String?
    ) -> BuildModel {
        BuildModel(
            id: id,
            uploadedDate: uploadedDate,
            iconUrl: iconUrl,
            platform: platform
        )
    }

    /// `Date(timeIntervalSince1970:)` sugar so tests read as relative ages.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
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

    // MARK: - Platform icons

    func testPlatformIconsGroupsByPlatformAndPicksNewestIcon() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: date(100), iconUrl: "https://cdn/ios-old.png", platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(300), iconUrl: "https://cdn/ios-new.png", platform: "IOS"),
            makeBuild(id: "b3", uploadedDate: date(200), iconUrl: "https://cdn/tv.png", platform: "TV_OS")
        ]

        let icons = AppDetailViewModel.platformIcons(from: builds)

        XCTAssertEqual(icons.count, 2)
        XCTAssertEqual(icons[.ios], "https://cdn/ios-new.png")
        XCTAssertEqual(icons[.tvOs], "https://cdn/tv.png")
    }

    func testPlatformIconsSkipsNilOrEmptyIconAndFallsBackToNextNewest() {
        let builds = [
            // Newest iOS build has no usable icon → should fall through.
            makeBuild(id: "b1", uploadedDate: date(400), iconUrl: nil, platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(300), iconUrl: "", platform: "IOS"),
            makeBuild(id: "b3", uploadedDate: date(200), iconUrl: "https://cdn/ios-fallback.png", platform: "IOS")
        ]

        let icons = AppDetailViewModel.platformIcons(from: builds)

        XCTAssertEqual(icons[.ios], "https://cdn/ios-fallback.png")
    }

    func testPlatformIconsExcludesUnmappedPlatformStrings() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: date(100), iconUrl: "https://cdn/ios.png", platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(100), iconUrl: "https://cdn/watch.png", platform: "WATCH_OS")
        ]

        let icons = AppDetailViewModel.platformIcons(from: builds)

        XCTAssertEqual(icons.count, 1)
        XCTAssertEqual(icons[.ios], "https://cdn/ios.png")
    }

    func testPlatformIconsTreatsNilUploadedDateAsOldest() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: nil, iconUrl: "https://cdn/ios-undated.png", platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(50), iconUrl: "https://cdn/ios-dated.png", platform: "IOS")
        ]

        let icons = AppDetailViewModel.platformIcons(from: builds)

        // The dated build outranks the undated one even though it appears later.
        XCTAssertEqual(icons[.ios], "https://cdn/ios-dated.png")
    }

    func testPlatformIconsWithNoIconBearingBuildOmitsPlatform() {
        let builds = [
            makeBuild(id: "b1", uploadedDate: date(100), iconUrl: nil, platform: "IOS"),
            makeBuild(id: "b2", uploadedDate: date(200), iconUrl: "", platform: "IOS")
        ]

        let icons = AppDetailViewModel.platformIcons(from: builds)

        XCTAssertNil(icons[.ios])
        XCTAssertTrue(icons.isEmpty)
    }

    func testPlatformIconsEmptyInputReturnsEmptyMap() {
        XCTAssertTrue(AppDetailViewModel.platformIcons(from: []).isEmpty)
    }
}
