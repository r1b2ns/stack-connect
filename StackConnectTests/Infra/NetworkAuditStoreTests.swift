import XCTest
@testable import StackConnect

final class NetworkAuditStoreTests: XCTestCase {

    private var directory: URL!
    private var sut: FileNetworkAuditStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkAuditStoreTests-\(UUID().uuidString)", isDirectory: true)
        sut = FileNetworkAuditStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        sut = nil
        directory = nil
        super.tearDown()
    }

    private func event(daysAgo: Double, hours: Double = 0) -> NetworkAuditEvent {
        let date = NetworkAuditFixtures.now.addingTimeInterval(-(daysAgo * 86_400) - hours * 3_600)
        return NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(startedAt: date))
    }

    func testAppendedEventsRoundTripNewestFirst() async throws {
        let old = event(daysAgo: 2)
        let recent = event(daysAgo: 0)
        await sut.append(old)
        await sut.append(recent)

        let summaries = await sut.summaries(since: .distantPast)

        XCTAssertEqual(summaries.map(\.id), [recent.id, old.id])
        let loaded = await sut.event(for: summaries[0])
        XCTAssertEqual(loaded, recent)
    }

    func testSummariesHonorTheCutoff() async {
        await sut.append(event(daysAgo: 20))
        let kept = event(daysAgo: 3)
        await sut.append(kept)

        let summaries = await sut.summaries(since: NetworkAuditRetention.sevenDays.cutoff(from: NetworkAuditFixtures.now))

        XCTAssertEqual(summaries.map(\.id), [kept.id])
    }

    func testPurgeRemovesWholeDaysAndFiltersTheBoundaryDay() async {
        let cutoff = NetworkAuditFixtures.now.addingTimeInterval(-7 * 86_400)
        let wholeDayOld = event(daysAgo: 10)
        let boundaryOld = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(startedAt: cutoff.addingTimeInterval(-60)))
        let boundaryKept = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(startedAt: cutoff.addingTimeInterval(60)))
        let recent = event(daysAgo: 1)
        for item in [wholeDayOld, boundaryOld, boundaryKept, recent] {
            await sut.append(item)
        }

        let countBefore = await sut.count(before: cutoff)
        let removed = await sut.purge(before: cutoff)
        let remaining = await sut.summaries(since: .distantPast)

        XCTAssertEqual(countBefore, 2)
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(Set(remaining.map(\.id)), [boundaryKept.id, recent.id])
        let purgedDetail = await sut.event(for: boundaryOld.summary)
        XCTAssertNil(purgedDetail)
        let keptDetail = await sut.event(for: boundaryKept.summary)
        XCTAssertNotNil(keptDetail)
    }

    func testDeleteAllEmptiesTheLog() async {
        await sut.append(event(daysAgo: 0))
        await sut.append(event(daysAgo: 1))

        await sut.deleteAll()

        let summaries = await sut.summaries(since: .distantPast)
        let stats = await sut.stats()
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertEqual(stats, .empty)
    }

    func testStatsCountSizeAndOldest() async {
        let oldest = event(daysAgo: 5)
        await sut.append(oldest)
        await sut.append(event(daysAgo: 0))

        let stats = await sut.stats()

        XCTAssertEqual(stats.eventCount, 2)
        XCTAssertGreaterThan(stats.byteCount, 0)
        XCTAssertEqual(stats.oldestDate, oldest.date)
    }

    func testLogDirectoryIsExcludedFromBackup() async throws {
        await sut.append(event(daysAgo: 0))

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testStoredFilesNeverContainTheRealToken() async throws {
        let token = NetworkAuditFixtures.ascJWT(expiresAt: NetworkAuditFixtures.now.addingTimeInterval(600))
        await sut.append(NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(authorization: "Bearer \(token)")))

        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let file as URL in enumerator where !file.hasDirectoryPath {
            let content = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(content.contains(token), file.lastPathComponent)
            scanned += 1
        }
        XCTAssertEqual(scanned, 2)
    }

    func testRetentionCutoffAndDefault() {
        XCTAssertEqual(NetworkAuditRetention.default, .fifteenDays)
        let cutoff = NetworkAuditRetention.thirtyDays.cutoff(from: NetworkAuditFixtures.now, calendar: NetworkAuditFixtures.utcCalendar)
        XCTAssertEqual(cutoff, NetworkAuditFixtures.now.addingTimeInterval(-30 * 86_400))
    }

    func testSettingsDefaultsAndPersistence() {
        let suite = "NetworkAuditSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NetworkAuditSettings(defaults: defaults)

        XCTAssertEqual(settings.retention, .fifteenDays)
        XCTAssertTrue(settings.recordsFullBodies)

        settings.retention = .sevenDays
        settings.recordsFullBodies = false

        let reloaded = NetworkAuditSettings(defaults: defaults)
        XCTAssertEqual(reloaded.retention, .sevenDays)
        XCTAssertFalse(reloaded.recordsFullBodies)
    }
}
