import XCTest
import StackProtocols
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
    private var analytics: MockAnalyticsTracker!

    private let account = AccountModel(name: "Apple", providerType: .apple)

    override func setUp() async throws {
        try await super.setUp()
        mockStorage = MockPersistentStorable()
        mockKeychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        mockStorage = nil
        mockKeychain = nil
        analytics = nil
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
            keychain: mockKeychain,
            analytics: analytics
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

    // MARK: - Analytics events
    //
    // No credentials are stored, so API-backed actions take their failure path
    // offline; success paths need a live App Store Connect connection.

    func testRefreshTracksNothingAndPullToRefreshTracksFailure() async {
        let sut = makeSUT(version: makeVersion())

        await sut.refresh()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.pullToRefresh()
        XCTAssertEqual(analytics.trackedEvents, [.action(.refresh, on: .versionDetail, result: .failure)])
    }

    func testVersionActionsTrackFailureWithoutCredentials() async {
        let sut = makeSUT(version: makeVersion())

        await sut.submitForReview()
        await sut.cancelReview()
        await sut.cancelSubmission()
        await sut.releaseVersion()
        await sut.rejectVersion()

        XCTAssertEqual(analytics.trackedEvents, [
            .action(.submitForReview, on: .versionDetail, result: .failure),
            .action(.cancelReview, on: .versionDetail, result: .failure),
            .action(.cancelSubmission, on: .versionDetail, result: .failure),
            .action(.releaseVersion, on: .versionDetail, result: .failure),
            .action(.rejectVersion, on: .versionDetail, result: .failure)
        ])
    }

    func testStartSubmitTracksValidationFailureWithoutCredentials() async {
        let sut = makeSUT(version: makeVersion())

        await sut.startSubmitForReview()

        XCTAssertEqual(analytics.trackedEvents, [.action(.preSubmitValidation, on: .versionDetail, result: .failure)])
    }

    func testSaveGroupedFieldsTracksTapAndFailure() async {
        let sut = makeSUT(version: makeVersion())

        await sut.saveGroupedFields()

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.save, on: .versionDetail),
            .action(.saveVersionMetadata, on: .versionDetail, result: .failure)
        ])
    }

    func testSaveReleaseTypeTracksTheSelectedTypeOnly() async {
        let sut = makeSUT(version: makeVersion())
        sut.uiState.selectedReleaseType = .afterApproval

        await sut.saveReleaseType()

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.save, on: .versionRelease),
            .action(.updateReleaseType, on: .versionRelease, result: .failure, parameters: [
                AnalyticsParameterKey.kind: .string("afterApproval")
            ])
        ])
    }

    func testSavePhasedReleaseTracksTheChosenOption() async {
        let sut = makeSUT(version: makeVersion())

        await sut.savePhasedRelease(usePhased: true)
        await sut.savePhasedRelease(usePhased: false)

        XCTAssertEqual(analytics.taps(of: .usePhasedRelease), [.buttonTap(.usePhasedRelease, on: .phasedRelease)])
        XCTAssertEqual(analytics.taps(of: .releaseImmediately), [.buttonTap(.releaseImmediately, on: .phasedRelease)])
        XCTAssertEqual(analytics.results(of: .updatePhasedRelease), [.failure, .failure])
    }

    func testAttachBuildTracksFailureWithoutCredentials() async {
        let sut = makeSUT(version: makeVersion())

        await sut.attachBuild(BuildModel(id: "b1", uploadedDate: nil, iconUrl: nil, platform: "IOS"))

        XCTAssertEqual(analytics.trackedEvents, [.action(.selectBuild, on: .buildPicker, result: .failure)])
    }

    func testTextUpdateWithoutLocalizationTracksOnlyTheTap() async throws {
        let sut = makeSUT(version: makeVersion())

        try await sut.updatePromotionalText()

        XCTAssertEqual(analytics.trackedEvents, [.buttonTap(.save, on: .versionPromotionalText)])
    }
}
