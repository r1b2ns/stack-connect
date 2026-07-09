import XCTest
@testable import StackConnect

/// Covers the offline-first cache path of `VersionDetailViewModel.refresh()`.
///
/// The ViewModel builds its `AppleAccountConnection` internally from Keychain
/// credentials (no injectable connection seam), so these tests drive the
/// cache-read path only: with no credentials, `refresh()` populates state from
/// local storage and returns before any network fetch. This mirrors what the
/// user sees offline.
@MainActor
final class VersionDetailViewModelTests: XCTestCase {

    private var mockStorage: MockPersistentStorable!
    private var mockKeychain: MockKeyStorable!

    private let account = AccountModel(name: "Apple", providerType: .apple)

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

    private func makeVersion(id: String = "v1") -> AppStoreVersionModel {
        AppStoreVersionModel(
            id: id,
            platform: .ios,
            appStoreState: .prepareForSubmission,
            versionString: "3.1.0",
            appId: "app-1"
        )
    }

    /// Builds the SUT. `mockKeychain` has no credentials, so `createConnection()`
    /// returns nil and `refresh()` exercises only the cache-read path.
    private func makeSUT(version: AppStoreVersionModel) -> VersionDetailViewModel {
        VersionDetailViewModel(
            version: version,
            account: account,
            storage: mockStorage,
            keychain: mockKeychain
        )
    }

    private func seedLocalizations(_ localizations: [AppStoreLocalizationModel], versionId: String) async throws {
        try await mockStorage.save(
            CachedVersionLocalizations(id: versionId, localizations: localizations),
            id: versionId
        )
    }

    private func seedBuild(_ build: BuildModel, versionId: String) async throws {
        try await mockStorage.save(build, id: "build.\(versionId)")
    }

    private func seedPhased(_ phased: PhasedReleaseModel, versionId: String) async throws {
        try await mockStorage.save(phased, id: "phased.\(versionId)")
    }

    // MARK: - Cache read: localizations

    func testRefreshLoadsCachedLocalizationsAndEditorFields() async throws {
        let version = makeVersion()
        let localization = AppStoreLocalizationModel(
            id: "loc-en",
            locale: "en-US",
            description: "Cached description",
            keywords: "cached,keywords",
            promotionalText: "Cached promo",
            supportUrl: "https://support.example.com",
            marketingUrl: "https://marketing.example.com",
            whatsNew: "Cached what's new"
        )
        try await seedLocalizations([localization], versionId: version.id)

        let sut = makeSUT(version: version)
        await sut.refresh()

        XCTAssertEqual(sut.uiState.localizations.count, 1)
        XCTAssertEqual(sut.uiState.localization?.id, "loc-en")
        XCTAssertEqual(sut.uiState.editWhatsNew, "Cached what's new")
        XCTAssertEqual(sut.uiState.editPromotionalText, "Cached promo")
        XCTAssertEqual(sut.uiState.editDescription, "Cached description")
        XCTAssertEqual(sut.uiState.editKeywords, "cached,keywords")
        XCTAssertEqual(sut.uiState.editSupportUrl, "https://support.example.com")
        XCTAssertEqual(sut.uiState.editMarketingUrl, "https://marketing.example.com")
    }

    // MARK: - Cache read: build

    func testRefreshLoadsCachedBuild() async throws {
        let version = makeVersion()
        try await seedBuild(BuildModel(id: "build-42", version: "42", marketingVersion: "3.1.0"), versionId: version.id)

        let sut = makeSUT(version: version)
        await sut.refresh()

        XCTAssertEqual(sut.uiState.currentBuild?.id, "build-42")
        XCTAssertEqual(sut.uiState.currentBuild?.version, "42")
    }

    // MARK: - Cache read: phased release

    func testRefreshLoadsCachedPhasedRelease() async throws {
        let version = makeVersion()
        try await seedPhased(
            PhasedReleaseModel(id: "phased-1", state: .active, currentDayNumber: 3),
            versionId: version.id
        )

        let sut = makeSUT(version: version)
        await sut.refresh()

        XCTAssertEqual(sut.uiState.phasedRelease?.id, "phased-1")
        XCTAssertEqual(sut.uiState.phasedRelease?.state, .active)
        XCTAssertEqual(sut.uiState.phasedRelease?.currentDayNumber, 3)
    }

    // MARK: - Cache read: all three together

    func testRefreshLoadsAllCachedVersionDetails() async throws {
        let version = makeVersion()
        try await seedLocalizations(
            [AppStoreLocalizationModel(id: "loc-en", whatsNew: "Offline notes")],
            versionId: version.id
        )
        try await seedBuild(BuildModel(id: "build-42"), versionId: version.id)
        try await seedPhased(PhasedReleaseModel(id: "phased-1", state: .paused), versionId: version.id)

        let sut = makeSUT(version: version)
        await sut.refresh()

        XCTAssertEqual(sut.uiState.editWhatsNew, "Offline notes")
        XCTAssertEqual(sut.uiState.currentBuild?.id, "build-42")
        XCTAssertEqual(sut.uiState.phasedRelease?.state, .paused)
    }

    // MARK: - No cache

    func testRefreshWithoutCacheLeavesDetailsEmpty() async throws {
        let version = makeVersion()

        let sut = makeSUT(version: version)
        await sut.refresh()

        XCTAssertTrue(sut.uiState.localizations.isEmpty)
        XCTAssertNil(sut.uiState.currentBuild)
        XCTAssertNil(sut.uiState.phasedRelease)
        XCTAssertEqual(sut.uiState.editWhatsNew, "")
    }
}
