import XCTest
import StackProtocols
@testable import StackConnect

/// Analytics events of the ASC analytics-report screens (dashboard, report menu,
/// report detail and downloaded files).
@MainActor
final class AnalyticsReportsViewModelsAnalyticsTests: XCTestCase {

    private var analytics: MockAnalyticsTracker!

    override func setUp() async throws {
        try await super.setUp()
        analytics = MockAnalyticsTracker()
    }

    override func tearDown() async throws {
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var appleAccount: AccountModel { AccountModel(name: "Team", providerType: .apple) }
    private var sampleReport: AnalyticsCatalogReport { AnalyticsCatalog.sections[0].reports[0] }

    private func makeFilesSUT() -> AnalyticsReportFilesViewModel {
        AnalyticsReportFilesViewModel(
            appId: "app-1",
            appName: "App",
            report: sampleReport,
            account: appleAccount,
            keychain: MockKeyStorable(),
            analytics: analytics
        )
    }

    /// Writes a throwaway CSV and exposes it as a selectable file item.
    private func makeTempFileItem() throws -> AnalyticsFileItem {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-files-\(UUID().uuidString).csv")
        try "a,b\n1,2\n".write(to: url, atomically: true, encoding: .utf8)
        return AnalyticsFileItem(
            id: url.path,
            url: url,
            granularity: .daily,
            displayName: "2026-01-01",
            downloadDate: Date(),
            sizeBytes: 8
        )
    }

    // MARK: - Dashboard

    func testDashboardLoadTracksNothing() async {
        let sut = AnalyticsDashboardViewModel(
            project: FirebaseProjectModel(id: "p", displayName: "P", projectId: "p"),
            account: AccountModel(name: "Firebase", providerType: .firebase),
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.load()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
    }

    func testDashboardRefreshTracksFailureWithoutCredentials() async {
        let sut = AnalyticsDashboardViewModel(
            project: FirebaseProjectModel(id: "p", displayName: "P", projectId: "p"),
            account: AccountModel(name: "Firebase", providerType: .firebase),
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.refresh()

        XCTAssertEqual(analytics.actions(of: .refresh), [.action(.refresh, on: .analyticsDashboard, result: .failure)])
    }

    // MARK: - Reports menu

    func testToggleFavoriteTracksTapAndEnabledState() {
        let sut = AnalyticsReportsViewModel(
            appId: "app-1",
            appName: "App",
            account: appleAccount,
            storage: MockKeyStorable(),
            analytics: analytics
        )

        sut.toggleFavorite(sampleReport)
        sut.toggleFavorite(sampleReport)

        XCTAssertEqual(analytics.taps(of: .favorite).count, 2)
        XCTAssertEqual(analytics.actions(of: .toggleFavorite), [
            .action(.toggleFavorite, on: .analyticsReports, result: .success, parameters: [AnalyticsParameterKey.enabled: .bool(true)]),
            .action(.toggleFavorite, on: .analyticsReports, result: .success, parameters: [AnalyticsParameterKey.enabled: .bool(false)])
        ])
    }

    func testToggleHiddenTracksTapAndEnabledState() {
        let sut = AnalyticsReportsViewModel(
            appId: "app-1",
            appName: "App",
            account: appleAccount,
            storage: MockKeyStorable(),
            analytics: analytics
        )

        sut.toggleHidden(sampleReport)

        XCTAssertEqual(analytics.taps(of: .hide), [.buttonTap(.hide, on: .analyticsReports)])
        XCTAssertEqual(analytics.actions(of: .toggleHidden), [
            .action(.toggleHidden, on: .analyticsReports, result: .success, parameters: [AnalyticsParameterKey.enabled: .bool(true)])
        ])
    }

    // MARK: - Report detail

    func testEnableAndReactivateTrackTapAndFailureWithoutCredentials() async {
        let sut = AnalyticsReportDetailViewModel(
            appId: "app-1",
            appName: "App",
            report: sampleReport,
            account: appleAccount,
            keychain: MockKeyStorable(),
            defaults: MockKeyStorable(),
            analytics: analytics
        )

        await sut.enableReports()
        await sut.reactivateReports()

        XCTAssertEqual(analytics.taps(of: .enableReports), [.buttonTap(.enableReports, on: .analyticsReportDetail)])
        XCTAssertEqual(analytics.taps(of: .reactivate), [.buttonTap(.reactivate, on: .analyticsReportDetail)])
        XCTAssertEqual(analytics.actions(of: .enableReports), [.action(.enableReports, on: .analyticsReportDetail, result: .failure)])
        XCTAssertEqual(analytics.actions(of: .reactivateReports), [.action(.reactivateReports, on: .analyticsReportDetail, result: .failure)])
    }

    func testEnableWithoutPermissionTracksTapOnly() async {
        let sut = AnalyticsReportDetailViewModel(
            appId: "app-1",
            appName: "App",
            report: sampleReport,
            account: AccountModel(name: "Viewer", providerType: .apple, rules: AccountRules()),
            keychain: MockKeyStorable(),
            defaults: MockKeyStorable(),
            analytics: analytics
        )

        await sut.enableReports()

        XCTAssertEqual(analytics.taps(of: .enableReports).count, 1)
        XCTAssertTrue(analytics.actions(of: .enableReports).isEmpty)
    }

    // MARK: - Report files

    func testDeleteSelectedFilesTracksTapAndSuccessWithCounts() async throws {
        let sut = makeFilesSUT()
        let item = try makeTempFileItem()
        sut.uiState.itemsByGranularity = [.daily: [item]]
        sut.uiState.selectedIDs = [item.id]

        await sut.delete()

        XCTAssertEqual(analytics.taps(of: .confirmDelete), [.buttonTap(.confirmDelete, on: .analyticsReportFiles)])
        XCTAssertEqual(analytics.actions(of: .deleteFiles), [
            .action(.deleteFiles, on: .analyticsReportFiles, result: .success, parameters: [
                AnalyticsParameterKey.count: .int(1),
                AnalyticsParameterKey.failedCount: .int(0)
            ])
        ])
    }

    func testDeleteWithoutSelectionTracksTapOnly() async {
        let sut = makeFilesSUT()

        await sut.delete()

        XCTAssertEqual(analytics.taps(of: .confirmDelete).count, 1)
        XCTAssertTrue(analytics.actions(of: .deleteFiles).isEmpty)
    }

    func testShareSingleFileTracksTapAndSuccess() async throws {
        let sut = makeFilesSUT()
        let item = try makeTempFileItem()
        defer { try? FileManager.default.removeItem(at: item.url) }
        sut.uiState.itemsByGranularity = [.daily: [item]]
        sut.uiState.selectedIDs = [item.id]

        await sut.share()

        XCTAssertEqual(analytics.taps(of: .share), [.buttonTap(.share, on: .analyticsReportFiles)])
        XCTAssertEqual(analytics.actions(of: .shareFiles), [
            .action(.shareFiles, on: .analyticsReportFiles, result: .success, parameters: [AnalyticsParameterKey.count: .int(1)])
        ])
    }
}
