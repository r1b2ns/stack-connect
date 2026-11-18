import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class AppHistoryViewModelTests: XCTestCase {

    func testLoadTracksNothingAndRefreshTracksFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = AppHistoryViewModel(
            appId: "app-1",
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )

        await sut.load()
        XCTAssertTrue(analytics.trackedEvents.isEmpty)

        await sut.refresh()
        XCTAssertEqual(analytics.trackedEvents, [.action(.refresh, on: .appHistory, result: .failure)])
    }

    // MARK: - Timeline ordering (QA: "Released" dated before "Review Completed")

    private func day(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + n * 86_400) }

    private func build(
        versions: [AppStoreVersionModel],
        submissions: [ReviewSubmissionModel]
    ) -> [AppHistoryGroup] {
        AppHistoryTimelineBuilder.buildGroups(
            versions: versions,
            submissions: submissions,
            activityName: { "state-\($0.rawValue)" },
            submissionActivity: { "sub-\($0 ?? "nil")" }
        )
    }

    func testCurrentStateEntryIsUndatedAndPinnedFirst() {
        let version = AppStoreVersionModel(id: "v420", platform: .ios, appStoreState: .readyForSale,
                                           versionString: "4.2.0", createdDate: day(0), appId: "app")
        let submission = ReviewSubmissionModel(id: "s1", appId: "app", submittedDate: day(3),
                                               state: "COMPLETE", versionId: "v420")

        let entries = build(versions: [version], submissions: [submission]).first?.entries ?? []

        XCTAssertEqual(entries.map(\.id), ["v420-state", "sub-s1", "v420-created"])
        XCTAssertNil(entries[0].date, "ASC has no timestamp for the state change; it must not reuse createdDate.")
        XCTAssertEqual(entries[1].date, day(3))
        XCTAssertEqual(entries[2].date, day(0))
    }

    func testDatedEntriesAreNewestFirst() {
        let version = AppStoreVersionModel(id: "v", appStoreState: .readyForSale, createdDate: day(0), appId: "app")
        let submissions = [
            ReviewSubmissionModel(id: "old", appId: "app", submittedDate: day(1), state: "UNRESOLVED_ISSUES", versionId: "v"),
            ReviewSubmissionModel(id: "new", appId: "app", submittedDate: day(5), state: "COMPLETE", versionId: "v"),
            ReviewSubmissionModel(id: "other", appId: "app", submittedDate: day(9), state: "COMPLETE", versionId: "x")
        ]

        let entries = build(versions: [version], submissions: submissions).first?.entries ?? []

        XCTAssertEqual(entries.map(\.id), ["v-state", "sub-new", "sub-old", "v-created"])
        let dates = entries.compactMap(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testVersionsAreNewestFirstAndStateIsOptional() {
        let older = AppStoreVersionModel(id: "a", createdDate: day(0), appId: "app")
        let newer = AppStoreVersionModel(id: "b", appStoreState: .prepareForSubmission, createdDate: day(10), appId: "app")

        let groups = build(versions: [older, newer], submissions: [])

        XCTAssertEqual(groups.map(\.id), ["b", "a"])
        XCTAssertEqual(groups[1].entries.map(\.id), ["a-created"], "No state → only the created entry.")
    }
}
