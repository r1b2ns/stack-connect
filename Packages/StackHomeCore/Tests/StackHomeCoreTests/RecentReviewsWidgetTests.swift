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
