import XCTest
@testable import StackConnect

final class PreSubmitChecklistTests: XCTestCase {

    private func makeVersion(
        releaseType: String? = "MANUAL",
        versionString: String? = "3.1.0"
    ) -> AppStoreVersionModel {
        AppStoreVersionModel(
            id: "v1",
            appStoreState: .prepareForSubmission,
            versionString: versionString,
            releaseType: releaseType,
            appId: "app1"
        )
    }

    // MARK: - Validation

    func testFullySatisfiedChecklistIsValid() {
        let checklist = PreSubmitChecklist.make(
            version: makeVersion(),
            build: BuildModel(id: "b1", version: "42", marketingVersion: "3.1.0"),
            localizations: [AppStoreLocalizationModel(id: "l1", locale: "en-US", whatsNew: "Bug fixes")],
            reviewDetail: AppReviewDetailModel(id: "r1", isDemoAccountRequired: false),
            phasedRelease: nil,
            hasScreenshots: true
        )

        XCTAssertTrue(checklist.isValid)
        XCTAssertNil(checklist.validationMessage)
        XCTAssertTrue(checklist.missingRequirements.isEmpty)
        XCTAssertEqual(checklist.buildNumber, "3.1.0(42)")
        XCTAssertEqual(checklist.marketingVersion, "3.1.0")
        XCTAssertEqual(checklist.releaseType, .manual)
        XCTAssertFalse(checklist.phasedReleaseEnabled)
        XCTAssertTrue(checklist.demoAccountSatisfied)
    }

    func testMissingBuildWhatsNewAndScreenshots() {
        let checklist = PreSubmitChecklist.make(
            version: makeVersion(),
            build: nil,
            localizations: [AppStoreLocalizationModel(id: "l1", locale: "en-US", whatsNew: "   ")],
            reviewDetail: nil,
            phasedRelease: nil,
            hasScreenshots: false
        )

        XCTAssertFalse(checklist.isValid)
        XCTAssertEqual(Set(checklist.missingRequirements), [.build, .whatsNew, .screenshots])
        XCTAssertNotNil(checklist.validationMessage)
    }

    func testWhatsNewFilledWhenAnyLocalizationHasNotes() {
        let checklist = PreSubmitChecklist.make(
            version: makeVersion(),
            build: BuildModel(id: "b1", version: "1"),
            localizations: [
                AppStoreLocalizationModel(id: "l1", locale: "en-US", whatsNew: ""),
                AppStoreLocalizationModel(id: "l2", locale: "pt-BR", whatsNew: "Correções")
            ],
            reviewDetail: nil,
            phasedRelease: nil,
            hasScreenshots: true
        )

        XCTAssertTrue(checklist.whatsNewFilled)
        XCTAssertTrue(checklist.isValid)
    }

    func testDemoAccountRequiredButNotFilledBlocks() {
        let checklist = PreSubmitChecklist.make(
            version: makeVersion(),
            build: BuildModel(id: "b1", version: "1"),
            localizations: [AppStoreLocalizationModel(id: "l1", whatsNew: "notes")],
            reviewDetail: AppReviewDetailModel(
                id: "r1",
                demoAccountName: "",
                demoAccountPassword: "",
                isDemoAccountRequired: true
            ),
            phasedRelease: nil,
            hasScreenshots: true
        )

        XCTAssertEqual(checklist.missingRequirements, [.demoAccount])
        XCTAssertFalse(checklist.demoAccountSatisfied)
        XCTAssertFalse(checklist.isValid)
    }

    func testDemoAccountRequiredAndFilledIsValid() {
        let checklist = PreSubmitChecklist.make(
            version: makeVersion(),
            build: BuildModel(id: "b1", version: "1"),
            localizations: [AppStoreLocalizationModel(id: "l1", whatsNew: "notes")],
            reviewDetail: AppReviewDetailModel(
                id: "r1",
                demoAccountName: "demo",
                demoAccountPassword: "pw",
                isDemoAccountRequired: true
            ),
            phasedRelease: nil,
            hasScreenshots: true
        )

        XCTAssertTrue(checklist.isValid)
        XCTAssertTrue(checklist.demoAccountSatisfied)
    }

    func testDemoAccountNotRequiredIsSatisfiedEvenWhenEmpty() {
        let checklist = PreSubmitChecklist.make(
            version: makeVersion(),
            build: BuildModel(id: "b1", version: "1"),
            localizations: [AppStoreLocalizationModel(id: "l1", whatsNew: "notes")],
            reviewDetail: AppReviewDetailModel(id: "r1", isDemoAccountRequired: false),
            phasedRelease: nil,
            hasScreenshots: true
        )

        XCTAssertTrue(checklist.demoAccountSatisfied)
        XCTAssertTrue(checklist.isValid)
    }

    // MARK: - Mapping

    func testReleaseTypeAndPhasedMapping() {
        let checklist = PreSubmitChecklist.make(
            version: makeVersion(releaseType: "AFTER_APPROVAL"),
            build: BuildModel(id: "b1", version: "1"),
            localizations: [AppStoreLocalizationModel(id: "l1", whatsNew: "notes")],
            reviewDetail: nil,
            phasedRelease: PhasedReleaseModel(id: "p1", state: .inactive),
            hasScreenshots: true
        )

        XCTAssertEqual(checklist.releaseType, .afterApproval)
        XCTAssertTrue(checklist.phasedReleaseEnabled)
    }

    func testUnknownReleaseTypeFallsBackToManual() {
        let checklist = PreSubmitChecklist.make(
            version: makeVersion(releaseType: nil),
            build: BuildModel(id: "b1", version: "1"),
            localizations: [AppStoreLocalizationModel(id: "l1", whatsNew: "notes")],
            reviewDetail: nil,
            phasedRelease: nil,
            hasScreenshots: true
        )

        XCTAssertEqual(checklist.releaseType, .manual)
    }
}

// MARK: - Loader

@MainActor
final class PreSubmitChecklistLoaderTests: XCTestCase {

    private func makeVersion() -> AppStoreVersionModel {
        AppStoreVersionModel(
            id: "v1",
            appStoreState: .prepareForSubmission,
            versionString: "3.1.0",
            releaseType: "MANUAL",
            appId: "app1"
        )
    }

    func testLoadAggregatesDataAndDetectsScreenshots() async {
        let source = MockPreSubmitDataSource(
            build: BuildModel(id: "b1", version: "10", marketingVersion: "3.1.0"),
            localizations: [AppStoreLocalizationModel(id: "loc1", locale: "en-US", whatsNew: "Notes")],
            reviewDetail: AppReviewDetailModel(id: "r1", isDemoAccountRequired: false),
            screenshotSetsByLocalization: [
                "loc1": [ScreenshotSetModel(id: "set1", displayType: "APP_IPHONE_67", screenshots: [ScreenshotModel(id: "img1")])]
            ],
            phased: nil
        )

        let checklist = await PreSubmitChecklistLoader.load(source: source, version: makeVersion())

        XCTAssertTrue(checklist.hasBuild)
        XCTAssertEqual(checklist.buildNumber, "3.1.0(10)")
        XCTAssertTrue(checklist.whatsNewFilled)
        XCTAssertTrue(checklist.hasScreenshots)
        XCTAssertTrue(checklist.isValid)
    }

    func testLoadWithEmptyScreenshotSetsIsInvalid() async {
        let source = MockPreSubmitDataSource(
            build: BuildModel(id: "b1", version: "10"),
            localizations: [AppStoreLocalizationModel(id: "loc1", whatsNew: "Notes")],
            reviewDetail: nil,
            screenshotSetsByLocalization: [
                "loc1": [ScreenshotSetModel(id: "set1", displayType: "APP_IPHONE_67", screenshots: [])]
            ],
            phased: nil
        )

        let checklist = await PreSubmitChecklistLoader.load(source: source, version: makeVersion())

        XCTAssertFalse(checklist.hasScreenshots)
        XCTAssertEqual(checklist.missingRequirements, [.screenshots])
    }
}

private struct MockPreSubmitDataSource: PreSubmitChecklistDataSource {
    var build: BuildModel?
    var localizations: [AppStoreLocalizationModel]
    var reviewDetail: AppReviewDetailModel?
    var screenshotSetsByLocalization: [String: [ScreenshotSetModel]]
    var phased: PhasedReleaseModel?

    func fetchCurrentBuild(versionId: String) async throws -> BuildModel? { build }
    func fetchLocalizations(versionId: String) async throws -> [AppStoreLocalizationModel] { localizations }
    func fetchAppReviewDetail(versionId: String) async throws -> AppReviewDetailModel? { reviewDetail }
    func fetchScreenshotSets(localizationId: String) async throws -> [ScreenshotSetModel] {
        screenshotSetsByLocalization[localizationId] ?? []
    }
    func fetchPhasedRelease(versionId: String) async throws -> PhasedReleaseModel? { phased }
}
