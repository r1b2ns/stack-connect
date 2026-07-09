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

    // MARK: - File store path scheme

    private func makeInstance(id: String = "inst-1", processingDate: String? = "2025-06-30") -> AnalyticsReportInstanceModel {
        AnalyticsReportInstanceModel(id: id, granularity: "DAILY", processingDate: processingDate)
    }

    func testFileURLScopesByAppIdDirectoryAndAppNamePrefixedBasename() {
        let url = AnalyticsReportFileStore.fileURL(
            appId: "1234567890",
            appName: "My App",
            category: .appUsage,
            apiName: "App Sessions",
            granularity: .daily,
            instance: makeInstance()
        )

        // The <appId> directory scopes storage per app, and it sits above the
        // category directory in the path.
        let components = url.pathComponents
        let appIdIndex = try? XCTUnwrap(components.firstIndex(of: "1234567890"))
        let categoryIndex = try? XCTUnwrap(components.firstIndex(of: AnalyticsCategory.appUsage.rawValue))
        XCTAssertNotNil(appIdIndex)
        XCTAssertNotNil(categoryIndex)
        if let appIdIndex, let categoryIndex {
            XCTAssertLessThan(appIdIndex, categoryIndex, "<appId> must be a directory above <category>.")
        }

        // Basename: sanitized app name prefix + "-" + instance key + ".csv".
        XCTAssertEqual(url.lastPathComponent, "MyApp-20250630.csv")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("MyApp"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix("-20250630.csv"))
    }

    func testFileURLUsesInstanceIdInBasenameWhenNoProcessingDate() {
        let url = AnalyticsReportFileStore.fileURL(
            appId: "app.a",
            appName: "App A",
            category: .appUsage,
            apiName: "App Sessions",
            granularity: .weekly,
            instance: makeInstance(id: "opaque-id", processingDate: nil)
        )

        XCTAssertEqual(url.lastPathComponent, "AppA-opaque-id.csv")
    }

    func testDifferentAppIdsResolveToDifferentPathsForSameReportAndInstance() {
        let instance = makeInstance()
        let pathA = AnalyticsReportFileStore.fileURL(
            appId: "app.a",
            appName: "Shared Name",
            category: .appUsage,
            apiName: "App Sessions",
            granularity: .daily,
            instance: instance
        )
        let pathB = AnalyticsReportFileStore.fileURL(
            appId: "app.b",
            appName: "Shared Name",
            category: .appUsage,
            apiName: "App Sessions",
            granularity: .daily,
            instance: instance
        )

        XCTAssertNotEqual(pathA, pathB, "Two apps sharing the same report/instance must not collide on disk.")
    }

    func testBlankAppNameFallsBackToAppIdInFilenamePrefix() {
        let url = AnalyticsReportFileStore.fileURL(
            appId: "1234567890",
            appName: "   ", // sanitizes to empty
            category: .appUsage,
            apiName: "App Sessions",
            granularity: .daily,
            instance: makeInstance()
        )

        XCTAssertEqual(url.lastPathComponent, "1234567890-20250630.csv")
    }

    func testAppFilenamePrefixUsesSanitizedAppNameOtherwiseAppId() {
        XCTAssertEqual(
            AnalyticsReportFileStore.appFilenamePrefix(appName: "My App", appId: "id-1"),
            "MyApp"
        )
        XCTAssertEqual(
            AnalyticsReportFileStore.appFilenamePrefix(appName: "", appId: "id-1"),
            "id-1"
        )
    }

    // MARK: - Legacy un-scoped file purge

    /// Fresh isolated temp directory so the purge never touches real Application
    /// Support. Caller is responsible for removing it (tests use `defer`).
    private func makeTempBaseDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsPurgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Builds `<base>/<top>/<sub…>/<file>` and returns the top-level `<top>` URL.
    @discardableResult
    private func makeReportTree(in base: URL, top: String, sub: [String], file: String) throws -> URL {
        let fm = FileManager.default
        var dir = base.appendingPathComponent(top, isDirectory: true)
        for component in sub {
            dir.appendPathComponent(component, isDirectory: true)
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let created = fm.createFile(atPath: dir.appendingPathComponent(file).path, contents: Data("csv".utf8))
        XCTAssertTrue(created, "Failed to seed fixture file at \(dir.path)/\(file)")
        return base.appendingPathComponent(top, isDirectory: true)
    }

    func testPurgeRemovesLegacyCategoryRootButKeepsAppIdRoot() throws {
        let fm = FileManager.default
        let base = try makeTempBaseDirectory()
        defer { try? fm.removeItem(at: base) }

        // Legacy: category-rooted, no appId — `<base>/APP_USAGE/AppSessions/DAILY/x.csv`.
        let legacyRoot = try makeReportTree(
            in: base, top: "APP_USAGE", sub: ["AppSessions", "DAILY"], file: "x.csv"
        )
        // Current: appId-rooted — `<base>/1234567890/COMMERCE/AppSessions/DAILY/MyApp-x.csv`.
        let appIdRoot = try makeReportTree(
            in: base, top: "1234567890", sub: ["COMMERCE", "AppSessions", "DAILY"], file: "MyApp-x.csv"
        )

        AnalyticsReportFileStore.purgeLegacyUnscopedFiles(in: base)

        XCTAssertFalse(
            fm.fileExists(atPath: legacyRoot.path),
            "The legacy category-rooted directory must be removed."
        )
        XCTAssertTrue(
            fm.fileExists(atPath: appIdRoot.path),
            "The numeric appId root must be left untouched."
        )
    }

    func testPurgePreservesAppIdRootThatContainsACategorySubdirectory() throws {
        let fm = FileManager.default
        let base = try makeTempBaseDirectory()
        defer { try? fm.removeItem(at: base) }

        // An appId-named top-level dir whose *child* is a category. Only exact
        // top-level category-named dirs are removed — never a nested one.
        let appIdRoot = try makeReportTree(
            in: base, top: "987654321", sub: ["APP_USAGE", "AppSessions", "DAILY"], file: "MyApp-x.csv"
        )
        let nestedCategory = appIdRoot.appendingPathComponent("APP_USAGE", isDirectory: true)

        AnalyticsReportFileStore.purgeLegacyUnscopedFiles(in: base)

        XCTAssertTrue(
            fm.fileExists(atPath: appIdRoot.path),
            "The appId root must be preserved."
        )
        XCTAssertTrue(
            fm.fileExists(atPath: nestedCategory.path),
            "A category directory nested under an appId root must be preserved."
        )
    }

    func testPurgeRemovesEveryKnownLegacyCategoryRoot() throws {
        let fm = FileManager.default
        let base = try makeTempBaseDirectory()
        defer { try? fm.removeItem(at: base) }

        for category in AnalyticsCategory.allCases {
            try makeReportTree(in: base, top: category.rawValue, sub: ["Api", "DAILY"], file: "x.csv")
        }

        AnalyticsReportFileStore.purgeLegacyUnscopedFiles(in: base)

        for category in AnalyticsCategory.allCases {
            let root = base.appendingPathComponent(category.rawValue, isDirectory: true)
            XCTAssertFalse(
                fm.fileExists(atPath: root.path),
                "Legacy root \(category.rawValue) must be removed."
            )
        }
    }

    func testPurgeOnNonexistentBaseDirectoryDoesNotCrash() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsPurgeMissing-\(UUID().uuidString)", isDirectory: true)

        // Must simply return without throwing or crashing.
        AnalyticsReportFileStore.purgeLegacyUnscopedFiles(in: missing)

        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testPurgeOnEmptyBaseDirectoryDoesNotCrash() throws {
        let base = try makeTempBaseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        AnalyticsReportFileStore.purgeLegacyUnscopedFiles(in: base)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: base.path),
            "An empty base directory should be left intact."
        )
    }
}
