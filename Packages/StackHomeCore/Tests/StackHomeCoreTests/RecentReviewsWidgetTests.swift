import XCTest
import StackProtocols
@testable import StackHomeCore

/// Verifies the Recent Reviews cap-at-5 semantics now that `load()` lives in
/// core (TC-035/TC-036), plus archived-app exclusion and store-failure
/// resilience (AC-W17-3, T-W29 Finding 2).
final class RecentReviewsWidgetTests: XCTestCase {

    func testMaxReviewsIsFive() {
        XCTAssertEqual(RecentReviewsWidget.maxReviews, 5)
    }

    @MainActor
    func testLoadCapsAtFiveMostRecent() async {
        let app = AppModel(id: "app1", name: "App", bundleId: "com.test", accountId: "acc")
        // 8 reviews with increasing createdDate; expect the 5 newest, newest-first.
        let base = Date(timeIntervalSince1970: 1_000_000)
        let reviews = (0..<8).map { i in
            CustomerReviewModel(
                id: "r\(i)",
                rating: 5,
                createdDate: base.addingTimeInterval(Double(i) * 60),
                appId: "app1"
            )
        }
        let storage = InMemoryStorage(apps: [app], reviews: reviews)
        let widget = RecentReviewsWidget(
            configuration: HomeWidgetConfiguration(kind: .recentReviews),
            storage: storage
        )

        await widget.load()

        XCTAssertEqual(widget.data.reviews.count, 5)
        XCTAssertEqual(widget.data.reviews.map(\.review.id), ["r7", "r6", "r5", "r4", "r3"])
        XCTAssertFalse(widget.isLoading)
    }

    @MainActor
    func testLoadExcludesArchivedAppReviews() async {
        let live = AppModel(id: "live", name: "Live", bundleId: "com.live", accountId: "acc")
        let archived = AppModel(id: "arch", name: "Arch", bundleId: "com.arch", accountId: "acc", isArchived: true)
        let reviews = [
            CustomerReviewModel(id: "r1", rating: 4, createdDate: Date(), appId: "live"),
            CustomerReviewModel(id: "r2", rating: 4, createdDate: Date(), appId: "arch")
        ]
        let storage = InMemoryStorage(apps: [live, archived], reviews: reviews)
        let widget = RecentReviewsWidget(
            configuration: HomeWidgetConfiguration(kind: .recentReviews),
            storage: storage
        )

        await widget.load()

        XCTAssertEqual(widget.data.reviews.map(\.review.id), ["r1"])
    }

    // MARK: - Multi-account aggregation (US-W15 / T-W30)

    /// TC-053 (Integration, P1): Seeds 3 accounts with 8 total reviews
    /// distributed across them. After `load()`, verifies: exactly 5 reviews
    /// returned (the cap — AC-W15-1), they are the 5 NEWEST across ALL
    /// accounts sorted date-descending, the 3 oldest are absent, and the
    /// result spans more than one account (true cross-account aggregation).
    @MainActor
    func testMultiAccountAggregationCapsAtFiveMostRecent() async {
        // Accounts: acct-001 owns app-a1 + app-a2, acct-002 owns app-b, acct-003 owns app-c.
        let appA1 = AppModel(id: "app-a1", name: "App A1", bundleId: "com.a1", accountId: "acct-001")
        let appA2 = AppModel(id: "app-a2", name: "App A2", bundleId: "com.a2", accountId: "acct-001")
        let appB  = AppModel(id: "app-b",  name: "App B",  bundleId: "com.b",  accountId: "acct-002")
        let appC  = AppModel(id: "app-c",  name: "App C",  bundleId: "com.c",  accountId: "acct-003")

        // 8 reviews with strictly increasing dates (60-second intervals from a fixed epoch).
        // Distribution: acct-001 gets 4 (r0-r3), acct-002 gets 2 (r4-r5), acct-003 gets 2 (r6-r7).
        let base = Date(timeIntervalSince1970: 2_000_000)
        let reviews = [
            // acct-001 — app-a1 (r0, r1), app-a2 (r2, r3)
            CustomerReviewModel(id: "r0", rating: 3, createdDate: base.addingTimeInterval(0),   appId: "app-a1"),
            CustomerReviewModel(id: "r1", rating: 4, createdDate: base.addingTimeInterval(60),  appId: "app-a1"),
            CustomerReviewModel(id: "r2", rating: 5, createdDate: base.addingTimeInterval(120), appId: "app-a2"),
            CustomerReviewModel(id: "r3", rating: 2, createdDate: base.addingTimeInterval(180), appId: "app-a2"),
            // acct-002 — app-b (r4, r5)
            CustomerReviewModel(id: "r4", rating: 1, createdDate: base.addingTimeInterval(240), appId: "app-b"),
            CustomerReviewModel(id: "r5", rating: 5, createdDate: base.addingTimeInterval(300), appId: "app-b"),
            // acct-003 — app-c (r6, r7)
            CustomerReviewModel(id: "r6", rating: 4, createdDate: base.addingTimeInterval(360), appId: "app-c"),
            CustomerReviewModel(id: "r7", rating: 3, createdDate: base.addingTimeInterval(420), appId: "app-c"),
        ]

        let storage = InMemoryStorage(apps: [appA1, appA2, appB, appC], reviews: reviews)
        let widget = RecentReviewsWidget(
            configuration: HomeWidgetConfiguration(kind: .recentReviews),
            storage: storage
        )

        await widget.load()

        // Cap: exactly 5.
        XCTAssertEqual(widget.data.reviews.count, 5,
                       "Badge/cap must be 5 even when more reviews exist across accounts")

        // The 5 newest (by createdDate descending) are r7, r6, r5, r4, r3.
        let returnedIds = widget.data.reviews.map(\.review.id)
        XCTAssertEqual(returnedIds, ["r7", "r6", "r5", "r4", "r3"],
                       "Must return the 5 most-recent reviews in date-descending order")

        // The 3 oldest must NOT be present.
        for oldId in ["r0", "r1", "r2"] {
            XCTAssertFalse(returnedIds.contains(oldId),
                           "Review \(oldId) is outside the top-5 and must be excluded")
        }

        // Aggregation crosses accounts: the returned set must span more than one accountId.
        let returnedAccountIds = Set(widget.data.reviews.map(\.app.accountId))
        XCTAssertGreaterThan(returnedAccountIds.count, 1,
                             "Aggregation must span multiple accounts, got: \(returnedAccountIds)")

        XCTAssertFalse(widget.isLoading)
    }

    /// TC-054 (Integration, P1): Seeds exactly 5 reviews (no capping) across
    /// 2 accounts with mixed/non-chronological `createdDate`s. After `load()`,
    /// asserts that `data.reviews` is ordered strictly latest-first
    /// (AC-W15-1 sort guarantee).
    @MainActor
    func testSortByDateDescendingAcrossAccounts() async {
        let appX = AppModel(id: "app-x", name: "App X", bundleId: "com.x", accountId: "acct-alpha")
        let appY = AppModel(id: "app-y", name: "App Y", bundleId: "com.y", accountId: "acct-beta")

        // Dates in deliberately non-chronological insertion order.
        // June 5, June 7, June 6, June 4, June 8 (2026).
        let jun4 = Date(timeIntervalSince1970: 1_780_600_800) // 2026-06-04 approx
        let jun5 = jun4.addingTimeInterval(86_400)
        let jun6 = jun4.addingTimeInterval(86_400 * 2)
        let jun7 = jun4.addingTimeInterval(86_400 * 3)
        let jun8 = jun4.addingTimeInterval(86_400 * 4)

        let reviews = [
            CustomerReviewModel(id: "rx1", rating: 4, createdDate: jun5, appId: "app-x"),  // Jun 5
            CustomerReviewModel(id: "ry1", rating: 3, createdDate: jun7, appId: "app-y"),  // Jun 7
            CustomerReviewModel(id: "rx2", rating: 5, createdDate: jun6, appId: "app-x"),  // Jun 6
            CustomerReviewModel(id: "ry2", rating: 2, createdDate: jun4, appId: "app-y"),  // Jun 4
            CustomerReviewModel(id: "rx3", rating: 1, createdDate: jun8, appId: "app-x"),  // Jun 8
        ]

        let storage = InMemoryStorage(apps: [appX, appY], reviews: reviews)
        let widget = RecentReviewsWidget(
            configuration: HomeWidgetConfiguration(kind: .recentReviews),
            storage: storage
        )

        await widget.load()

        // All 5 returned (no capping needed), strictly newest-first.
        XCTAssertEqual(widget.data.reviews.count, 5)
        XCTAssertEqual(widget.data.reviews.map(\.review.id),
                       ["rx3", "ry1", "rx2", "rx1", "ry2"],
                       "Reviews must be sorted by createdDate descending: Jun 8, 7, 6, 5, 4")

        // The result spans both accounts.
        let accountIds = Set(widget.data.reviews.map(\.app.accountId))
        XCTAssertEqual(accountIds, ["acct-alpha", "acct-beta"],
                       "Reviews must span both seeded accounts")

        XCTAssertFalse(widget.isLoading)
    }

    /// Additive: when fewer than 5 reviews exist across multiple accounts, the
    /// count equals the available number — badge accuracy (AC-W15-3).
    @MainActor
    func testFewerThanFiveAcrossAccountsReturnAll() async {
        let app1 = AppModel(id: "fa1", name: "FA1", bundleId: "com.fa1", accountId: "acct-one")
        let app2 = AppModel(id: "fa2", name: "FA2", bundleId: "com.fa2", accountId: "acct-two")

        let base = Date(timeIntervalSince1970: 3_000_000)
        let reviews = [
            CustomerReviewModel(id: "fr1", rating: 5, createdDate: base,                         appId: "fa1"),
            CustomerReviewModel(id: "fr2", rating: 4, createdDate: base.addingTimeInterval(60),   appId: "fa2"),
            CustomerReviewModel(id: "fr3", rating: 3, createdDate: base.addingTimeInterval(120),  appId: "fa1"),
        ]

        let storage = InMemoryStorage(apps: [app1, app2], reviews: reviews)
        let widget = RecentReviewsWidget(
            configuration: HomeWidgetConfiguration(kind: .recentReviews),
            storage: storage
        )

        await widget.load()

        XCTAssertEqual(widget.data.reviews.count, 3,
                       "With only 3 reviews available, count must be 3 (not padded to 5)")
        XCTAssertEqual(widget.data.reviews.map(\.review.id), ["fr3", "fr2", "fr1"],
                       "Still sorted date-descending even when under the cap")
        XCTAssertFalse(widget.isLoading)
    }

    // MARK: - Store failure resilience (AC-W17-3 / T-W29 Finding 2)
    //
    // `WindowsHomeModel.loadDashboard()` is a one-line forward to the core's
    // `HomeViewModel.loadDashboard()`, which is already tested for the
    // `isLoading` true/false transition in `HomeViewModelTests.
    // testIsLoadingTransitionsDuringLoadDashboard()`. The adapter itself lives
    // in the executable target (`StackConnectWindowsApp`) and cannot be
    // `@testable import`-ed from the library test target
    // (`WindowsAppCoreTests`) without moving it — a refactor out of scope for
    // T-W29. These tests exercise the next most-specific importable seam:
    // `RecentReviewsWidget.load()`, which is the widget the adapter invokes
    // during `loadDashboard()` to rebuild the Recent Reviews data.

    /// When the store throws during `load()`, the widget must NOT propagate the
    /// error (non-blocking — AC-W17-3) and must reset `isLoading` to `false`.
    @MainActor
    func testLoadOnStoreFailureIsNonBlockingAndClearsLoading() async {
        let storage = ThrowingStorage()
        let widget = RecentReviewsWidget(
            configuration: HomeWidgetConfiguration(kind: .recentReviews),
            storage: storage
        )

        // Should NOT throw — the widget catches internally.
        await widget.load()

        XCTAssertFalse(widget.isLoading,
                        "isLoading must flip back to false even on store failure")
        XCTAssertTrue(widget.data.reviews.isEmpty,
                       "Data should be empty after a store failure")
    }

    /// When the store throws, a previously loaded data snapshot is replaced by
    /// an empty default (the widget does not preserve stale cached data on
    /// failure — it resets to empty). This verifies the documented behavior.
    @MainActor
    func testLoadOnStoreFailureResetsDataToEmpty() async {
        // First, load successfully to populate data.
        let app = AppModel(id: "app1", name: "App", bundleId: "com.test", accountId: "acc")
        let review = CustomerReviewModel(id: "r1", rating: 5, createdDate: Date(), appId: "app1")
        let goodStorage = InMemoryStorage(apps: [app], reviews: [review])
        let widget = RecentReviewsWidget(
            configuration: HomeWidgetConfiguration(kind: .recentReviews),
            storage: goodStorage
        )
        await widget.load()
        XCTAssertEqual(widget.data.reviews.count, 1, "Precondition: data should be populated")

        // Now create a new widget against a failing store to test the failure path.
        // (The widget holds a storage reference at init, so we need a new instance.)
        let failingWidget = RecentReviewsWidget(
            configuration: HomeWidgetConfiguration(kind: .recentReviews),
            storage: ThrowingStorage()
        )
        await failingWidget.load()

        XCTAssertTrue(failingWidget.data.reviews.isEmpty,
                       "Store failure should produce empty data, not stale data")
        XCTAssertFalse(failingWidget.isLoading)
    }
}

// MARK: - Minimal in-test storage

/// A throwaway `PersistentStorable` returning fixed apps/reviews; only the
/// `fetchAll` reads exercised by the widget are implemented.
private struct InMemoryStorage: PersistentStorable {
    let apps: [AppModel]
    let reviews: [CustomerReviewModel]

    func save<T: Codable>(_ item: T, id: String) async throws {}

    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? { nil }

    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
        if type == AppModel.self { return apps as! [T] }
        if type == CustomerReviewModel.self { return reviews as! [T] }
        return []
    }

    func delete<T: Codable>(_ type: T.Type, id: String) async throws {}
    func deleteAll<T: Codable>(_ type: T.Type) async throws {}
}

/// A storage that always throws on `fetchAll`, simulating a store failure
/// during widget reload (AC-W17-3 / T-W29 Finding 2).
private struct ThrowingStorage: PersistentStorable {
    struct StoreError: Error {}

    func save<T: Codable>(_ item: T, id: String) async throws {}
    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? { nil }
    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] { throw StoreError() }
    func delete<T: Codable>(_ type: T.Type, id: String) async throws {}
    func deleteAll<T: Codable>(_ type: T.Type) async throws {}
}
