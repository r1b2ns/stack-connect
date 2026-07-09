import XCTest
@testable import StackConnect

@MainActor
final class AnalyticsReportDetailViewModelTests: XCTestCase {

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

    /// First report in the first catalog section — a convenient sample.
    private var sampleReport: AnalyticsCatalogReport {
        AnalyticsCatalog.sections[0].reports[0]
    }

    /// Injects the mock as `defaults` (the request-time store); `keychain` keeps
    /// its default — these tests never touch credentials.
    private func makeSUT(appId: String = "app.a") -> AnalyticsReportDetailViewModel {
        AnalyticsReportDetailViewModel(
            appId: appId,
            appName: "App A",
            report: sampleReport,
            account: account,
            defaults: storage
        )
    }

    // MARK: - Request-time persistence

    func testRequestedAtIsNilWhenNothingStored() {
        let sut = makeSUT()

        XCTAssertNil(sut.requestedAt())
    }

    func testRecordRequestedNowRoundTripsToApproximatelyNow() throws {
        let sut = makeSUT()

        sut.recordRequestedNow()

        let stored = try XCTUnwrap(sut.requestedAt())
        XCTAssertLessThan(
            abs(stored.timeIntervalSinceNow),
            5,
            "Recorded time should round-trip to within a few seconds of now."
        )
    }

    func testRequestedAtIsScopedPerAppId() {
        let appA = makeSUT(appId: "app.a")
        appA.recordRequestedNow()

        let appB = makeSUT(appId: "app.b")

        XCTAssertNotNil(appA.requestedAt())
        XCTAssertNil(appB.requestedAt(), "A value recorded under app.a must not be visible from app.b.")
    }
}
