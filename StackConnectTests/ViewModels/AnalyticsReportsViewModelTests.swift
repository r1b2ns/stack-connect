import XCTest
@testable import StackConnect

@MainActor
final class AnalyticsReportsViewModelTests: XCTestCase {

    private var storage: MockKeyStorable!
    private var account: AccountModel!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockKeyStorable()
        account = AccountModel(name: "Test", providerType: .apple)
    }

    override func tearDown() async throws {
        storage = nil
        account = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT(appId: String = "app.a") -> AnalyticsReportsViewModel {
        AnalyticsReportsViewModel(
            appId: appId,
            appName: "App A",
            account: account,
            storage: storage
        )
    }

    /// First report in the first catalog section — a convenient sample.
    private var sampleReport: AnalyticsCatalogReport {
        AnalyticsCatalog.sections[0].reports[0]
    }

    private func catalogReportCount() -> Int {
        AnalyticsCatalog.sections.reduce(0) { $0 + $1.reports.count }
    }

    private func visibleReportCount(_ sut: AnalyticsReportsViewModel) -> Int {
        sut.sections.reduce(0) { $0 + $1.reports.count }
    }

    // MARK: - Initial state

    func testInitialStateExposesFullCatalogAndEmptyFavoritesAndHidden() {
        let sut = makeSUT()

        XCTAssertEqual(sut.sections.count, AnalyticsCatalog.sections.count)
        XCTAssertEqual(visibleReportCount(sut), catalogReportCount())
        XCTAssertTrue(sut.favoriteReports.isEmpty)
        XCTAssertTrue(sut.hiddenReports.isEmpty)
        XCTAssertFalse(sut.isHiddenSectionExpanded)
    }

    // MARK: - Favorite

    func testToggleFavoriteMovesReportOutOfCategoryIntoFavorites() {
        let sut = makeSUT()
        let report = sampleReport

        sut.toggleFavorite(report)

        XCTAssertEqual(sut.favoriteReports.map(\.id), [report.id])
        XCTAssertFalse(sut.sections.flatMap(\.reports).contains(report))
        XCTAssertEqual(visibleReportCount(sut), catalogReportCount() - 1)
    }

    func testToggleFavoriteOffRestoresReportToItsCategorySection() {
        let sut = makeSUT()
        let report = sampleReport

        sut.toggleFavorite(report)
        sut.toggleFavorite(report)

        XCTAssertTrue(sut.favoriteReports.isEmpty)
        XCTAssertTrue(sut.sections.flatMap(\.reports).contains(report))
        XCTAssertEqual(visibleReportCount(sut), catalogReportCount())
    }

    // MARK: - Hidden

    func testToggleHiddenMovesReportOutOfCategoryIntoHidden() {
        let sut = makeSUT()
        let report = sampleReport

        sut.toggleHidden(report)

        XCTAssertEqual(sut.hiddenReports.map(\.id), [report.id])
        XCTAssertFalse(sut.sections.flatMap(\.reports).contains(report))
        XCTAssertEqual(visibleReportCount(sut), catalogReportCount() - 1)
    }

    func testToggleHiddenOffRestoresReportToItsCategorySection() {
        let sut = makeSUT()
        let report = sampleReport

        sut.toggleHidden(report)
        sut.toggleHidden(report)

        XCTAssertTrue(sut.hiddenReports.isEmpty)
        XCTAssertTrue(sut.sections.flatMap(\.reports).contains(report))
    }

    // MARK: - Mutual exclusion

    func testFavoritingAHiddenReportUnhidesIt() {
        let sut = makeSUT()
        let report = sampleReport

        sut.toggleHidden(report)
        sut.toggleFavorite(report)

        XCTAssertEqual(sut.favoriteReports.map(\.id), [report.id])
        XCTAssertTrue(sut.hiddenReports.isEmpty)
    }

    func testHidingAFavoriteReportUnfavoritesIt() {
        let sut = makeSUT()
        let report = sampleReport

        sut.toggleFavorite(report)
        sut.toggleHidden(report)

        XCTAssertEqual(sut.hiddenReports.map(\.id), [report.id])
        XCTAssertTrue(sut.favoriteReports.isEmpty)
    }

    // MARK: - Ordering

    func testFavoriteReportsFollowCatalogOrderRegardlessOfToggleOrder() {
        let sut = makeSUT()
        let all = AnalyticsCatalog.sections.flatMap(\.reports)
        let first = all[0]
        let third = all[2]

        // Toggle out of catalog order.
        sut.toggleFavorite(third)
        sut.toggleFavorite(first)

        XCTAssertEqual(sut.favoriteReports.map(\.id), [first.id, third.id])
    }

    // MARK: - Hidden section expansion

    func testToggleHiddenSectionFlipsTheFlag() {
        let sut = makeSUT()

        XCTAssertFalse(sut.isHiddenSectionExpanded)
        sut.toggleHiddenSection()
        XCTAssertTrue(sut.isHiddenSectionExpanded)
        sut.toggleHiddenSection()
        XCTAssertFalse(sut.isHiddenSectionExpanded)
    }

    // MARK: - Persistence

    func testStateSurvivesAcrossViewModelInstancesForSameApp() {
        let report = sampleReport
        let hiddenReport = AnalyticsCatalog.sections[1].reports[0]

        let first = makeSUT(appId: "app.persist")
        first.toggleFavorite(report)
        first.toggleHidden(hiddenReport)

        let second = AnalyticsReportsViewModel(
            appId: "app.persist",
            appName: "App A",
            account: account,
            storage: storage
        )

        XCTAssertEqual(second.favoriteReports.map(\.id), [report.id])
        XCTAssertEqual(second.hiddenReports.map(\.id), [hiddenReport.id])
    }

    func testStateIsScopedPerAppId() {
        let report = sampleReport

        let appA = makeSUT(appId: "app.a")
        appA.toggleFavorite(report)

        let appB = AnalyticsReportsViewModel(
            appId: "app.b",
            appName: "App B",
            account: account,
            storage: storage
        )

        XCTAssertTrue(appB.favoriteReports.isEmpty)
        XCTAssertTrue(appB.hiddenReports.isEmpty)
        XCTAssertEqual(visibleReportCount(appB), catalogReportCount())
    }
}
