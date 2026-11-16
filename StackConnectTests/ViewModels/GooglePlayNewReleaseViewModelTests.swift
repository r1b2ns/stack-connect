import XCTest
@testable import StackConnect

/// New Release / Promote (plan T6): track hints, notes pre-filled from the
/// previous release of the track, the "higher than live" version code guard,
/// and the change handed to the Review Checklist.
@MainActor
final class GooglePlayNewReleaseViewModelTests: XCTestCase {

    private let live = GooglePlayReleaseModel(
        name: "4.2.0 (4210)", status: .inProgress, versionCodes: ["4210"], userFraction: 0.2,
        releaseNotes: [GooglePlayLocalizedTextModel(language: "en-US", text: "Shade forecast")], inAppUpdatePriority: 2
    )
    private let draft = GooglePlayReleaseModel(
        name: "4.3.0 (4305)", status: .draft, versionCodes: ["4305"], userFraction: nil,
        releaseNotes: [GooglePlayLocalizedTextModel(language: "en-US", text: "Trip planner")], inAppUpdatePriority: nil
    )

    private var tracks: [GooglePlayTrackModel] {
        [
            GooglePlayTrackModel(track: "production", releases: [live]),
            GooglePlayTrackModel(track: "internal", releases: [draft]),
            GooglePlayTrackModel(track: "city-partners", releases: [])
        ]
    }

    private func makeSUT(
        _ source: GooglePlayNewReleaseRequest.Source,
        bundles: [GooglePlayBundleModel] = [],
        bundlesError: Error? = nil
    ) -> GooglePlayNewReleaseViewModel {
        GooglePlayNewReleaseViewModel(
            request: GooglePlayNewReleaseRequest(source: source),
            tracks: tracks,
            listingLanguages: ["en-US", "pt-BR"],
            loadBundles: {
                if let bundlesError { throw bundlesError }
                return bundles
            }
        )
    }

    func testTrackOptionsDescribeWhatEachTrackServes() {
        let sut = makeSUT(.bundle(track: nil))

        XCTAssertEqual(sut.uiState.trackOptions.map(\.track), ["production", "beta", "alpha", "internal", "city-partners"])
        XCTAssertEqual(sut.uiState.trackOptions[0].hint, String(localized: "Live: \("4.2.0") at \(GooglePlayPendingWrite.percent(0.2))"))
        XCTAssertEqual(sut.uiState.trackOptions[1].hint, String(localized: "No releases"))
        XCTAssertEqual(sut.uiState.trackOptions[3].hint, String(localized: "Draft: \("4.3.0 (4305)")"))
        XCTAssertEqual(sut.uiState.track, "production")
    }

    func testNotesArePrefilledFromTheTracksPreviousReleaseUntilEdited() {
        let sut = makeSUT(.bundle(track: "production"))

        XCTAssertEqual(sut.uiState.languages, ["en-US", "pt-BR"])
        XCTAssertEqual(sut.uiState.notes["en-US"], "Shade forecast")
        XCTAssertEqual(sut.uiState.notesCopiedFrom, "4.2.0")

        sut.selectTrack("internal")
        XCTAssertEqual(sut.uiState.notes["en-US"], "Trip planner")

        sut.uiState.notes["en-US"] = "Mine"
        sut.notesChanged()
        sut.selectTrack("production")
        XCTAssertEqual(sut.uiState.notes["en-US"], "Mine", "Edited notes survive a track change")
    }

    func testVersionCodeMustBeHigherThanTheLiveOne() async {
        let sut = makeSUT(.bundle(track: "production"), bundles: [
            GooglePlayBundleModel(versionCode: "4306", sha256: nil),
            GooglePlayBundleModel(versionCode: "4200", sha256: nil)
        ])
        await sut.loadBundles()
        XCTAssertNil(sut.pendingWrite(), "No bundle yet")

        sut.selectBundle(GooglePlayBundleModel(versionCode: "4200", sha256: nil))
        XCTAssertNotNil(sut.uiState.versionCodeError)
        XCTAssertFalse(sut.uiState.canContinue)
        XCTAssertNil(sut.pendingWrite())

        sut.selectBundle(GooglePlayBundleModel(versionCode: "4306", sha256: nil))
        XCTAssertNil(sut.uiState.versionCodeError)
        XCTAssertTrue(sut.uiState.canContinue)
    }

    func testNewReleaseBecomesACreateChange() {
        let sut = makeSUT(.bundle(track: "production"))
        sut.selectBundle(GooglePlayBundleModel(versionCode: "4306", sha256: nil))
        sut.uiState.name = "4.3.1"
        sut.uiState.rolloutPercent = 5

        let write = sut.pendingWrite()

        XCTAssertEqual(write?.track, "production")
        XCTAssertEqual(write?.change, .create(GooglePlayNewRelease(
            versionCodes: ["4306"],
            name: "4.3.1",
            releaseNotes: [GooglePlayLocalizedTextModel(language: "en-US", text: "Shade forecast")],
            status: .inProgress(userFraction: 0.05),
            inAppUpdatePriority: nil
        )))
        XCTAssertTrue(write?.usesChecklist ?? false)

        sut.uiState.isDraft = true
        if case .create(let release)? = sut.pendingWrite()?.change {
            XCTAssertEqual(release.status, .draft)
        } else {
            XCTFail("Expected a create change")
        }
    }

    func testTracksWithoutStagedRolloutReleaseToAll() {
        let sut = makeSUT(.bundle(track: "alpha"))
        sut.selectBundle(GooglePlayBundleModel(versionCode: "4306", sha256: nil))

        XCTAssertFalse(sut.uiState.supportsStagedRollout)
        XCTAssertEqual(sut.uiState.status, .completed)
    }

    func testPromotionTargetsTheNextTrackAndCopiesTheSourceRelease() {
        let sut = makeSUT(.promote(fromTrack: "internal", release: draft))

        XCTAssertEqual(sut.uiState.track, "alpha")
        XCTAssertFalse(sut.uiState.trackOptions.map(\.track).contains("internal"))
        XCTAssertEqual(sut.uiState.name, "4.3.0 (4305)")
        XCTAssertEqual(sut.uiState.notes["en-US"], "Trip planner")

        sut.selectTrack("production")
        let write = sut.pendingWrite()
        XCTAssertEqual(write?.change, .promote(
            fromTrack: "internal", versionCodes: ["4305"], status: .inProgress(userFraction: 0.1),
            name: "4.3.0 (4305)", releaseNotes: [GooglePlayLocalizedTextModel(language: "en-US", text: "Trip planner")],
            inAppUpdatePriority: nil
        ))
        XCTAssertEqual(write?.release, draft)
    }

    func testPromotingAReleaseNotAboveTheLiveOneIsRefused() {
        let old = GooglePlayReleaseModel(name: "4.1.0", status: .completed, versionCodes: ["4100"], userFraction: nil, releaseNotes: [], inAppUpdatePriority: nil)
        let sut = makeSUT(.promote(fromTrack: "internal", release: old))

        sut.selectTrack("production")

        XCTAssertNotNil(sut.uiState.versionCodeError)
        XCTAssertNil(sut.pendingWrite())
    }

    func testBundleLoadingFailureIsShown() async {
        let sut = makeSUT(.bundle(track: nil), bundlesError: OfflineError.noConnection)

        await sut.loadBundles()

        XCTAssertNotNil(sut.uiState.bundlesError)
        XCTAssertFalse(sut.uiState.isLoadingBundles)
    }
}
