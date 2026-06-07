import XCTest
import StackProtocols
@testable import StackHomeCore

/// Verifies the Recent Reviews cap-at-5 semantics now that `load()` lives in
/// core (TC-035/TC-036), plus archived-app exclusion.
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
