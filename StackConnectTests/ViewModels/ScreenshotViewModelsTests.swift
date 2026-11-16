import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics events of the screenshot preview / grid / page ViewModels.
@MainActor
final class ScreenshotViewModelsTests: XCTestCase {

    private let account = AccountModel(name: "Team", providerType: .apple)
    private let screenshots = [ScreenshotModel(id: "s1"), ScreenshotModel(id: "s2")]

    func testGridDeleteSelectedTracksCountAndFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = ScreenshotGridViewModel(
            screenshots: screenshots, account: account, appStoreState: .prepareForSubmission,
            keychain: MockKeyStorable(), analytics: analytics
        )
        sut.toggleSelection(screenshots[0])
        sut.toggleSelection(screenshots[1])

        await sut.deleteSelected()

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.confirmDelete, on: .screenshotGrid),
            .action(.deleteScreenshots, on: .screenshotGrid, result: .failure, parameters: [AnalyticsParameterKey.count: .int(2)])
        ])
    }

    func testPageDeleteTracksFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = ScreenshotPageViewModel(
            screenshots: screenshots, account: account, appStoreState: .prepareForSubmission,
            keychain: MockKeyStorable(), analytics: analytics
        )

        await sut.deleteScreenshot(screenshots[0])

        XCTAssertEqual(analytics.results(of: .deleteScreenshots), [.failure])
        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .screenshotPage)])
    }

    func testPreviewDeleteAllTracksFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = ScreenshotPreviewViewModel(
            versionId: "v1", account: account, appStoreState: .prepareForSubmission,
            keychain: MockKeyStorable(), analytics: analytics
        )
        sut.screenshotSets = [ScreenshotSetModel(id: "set-1", screenshots: screenshots)]

        await sut.deleteAllScreenshots()

        XCTAssertEqual(analytics.actions(of: .deleteScreenshots), [
            .action(.deleteScreenshots, on: .screenshotPreview, result: .failure, parameters: [AnalyticsParameterKey.count: .int(1)])
        ])
    }

    func testPreviewDownloadWithNothingToDownloadTracksOnlyTheTap() async {
        let analytics = MockAnalyticsTracker()
        let sut = ScreenshotPreviewViewModel(
            versionId: "v1", account: account, keychain: MockKeyStorable(), analytics: analytics
        )

        await sut.downloadAllScreenshots()

        XCTAssertEqual(analytics.trackedEvents, [.buttonTap(.downloadAll, on: .screenshotPreview)])
    }
}
