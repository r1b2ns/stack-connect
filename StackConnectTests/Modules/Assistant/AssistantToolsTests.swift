import XCTest
@testable import StackConnect
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
final class AssistantToolsTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var resolver: AppResolver!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        resolver = AppResolver(storage: storage)
    }

    override func tearDown() async throws {
        storage = nil
        resolver = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func review(
        id: String,
        rating: Int,
        appId: String,
        date: Date,
        title: String? = nil,
        body: String? = nil
    ) -> CustomerReviewModel {
        CustomerReviewModel(
            id: id,
            rating: rating,
            title: title,
            body: body,
            reviewerNickname: nil,
            createdDate: date,
            territory: nil,
            responseId: nil,
            responseBody: nil,
            responseState: nil,
            responseDate: nil,
            appId: appId
        )
    }

    // MARK: - ListAppsTool

    func testListAppsFormatsApps() async throws {
        try await storage.save(
            AppModel(
                id: "1",
                name: "Alpha",
                bundleId: "com.a",
                accountId: "acc",
                appStoreState: .readyForSale,
                versionString: "1.2.0"
            ),
            id: "1"
        )
        let tool = ListAppsTool(resolver: resolver)

        let output = await tool.run(nameFilter: nil)

        XCTAssertTrue(output.contains("Alpha"))
        XCTAssertTrue(output.contains("com.a"))
        XCTAssertTrue(output.contains("1.2.0"))
    }

    func testListAppsNoMatch() async throws {
        try await storage.save(
            AppModel(id: "1", name: "Alpha", bundleId: "com.a", accountId: "acc"),
            id: "1"
        )
        let tool = ListAppsTool(resolver: resolver)

        let output = await tool.run(nameFilter: "Nonexistent")

        XCTAssertTrue(output.localizedCaseInsensitiveContains("No app matches"))
    }

    func testListAppsEmptyStorage() async throws {
        let tool = ListAppsTool(resolver: resolver)

        let output = await tool.run(nameFilter: nil)

        XCTAssertTrue(output.localizedCaseInsensitiveContains("No apps"))
    }

    // MARK: - ListReviewsTool

    func testListReviewsSortsByDateDescAndLimits() async throws {
        try await storage.save(
            AppModel(id: "app1", name: "Alpha", bundleId: "com.a", accountId: "acc"),
            id: "app1"
        )
        try await storage.save(
            review(id: "old", rating: 3, appId: "app1", date: Date(timeIntervalSince1970: 100), body: "Oldest"),
            id: "review.app1.old"
        )
        try await storage.save(
            review(id: "new", rating: 5, appId: "app1", date: Date(timeIntervalSince1970: 999), body: "Newest"),
            id: "review.app1.new"
        )
        // Review belonging to another app must be ignored.
        try await storage.save(
            review(id: "other", rating: 1, appId: "app2", date: Date(timeIntervalSince1970: 500), body: "OtherApp"),
            id: "review.app2.other"
        )
        let tool = ListReviewsTool(resolver: resolver, storage: storage)

        let output = await tool.run(appName: "Alpha", limit: 1)

        XCTAssertTrue(output.contains("Most recent reviews for Alpha"))
        XCTAssertTrue(output.contains("Newest"))
        XCTAssertFalse(output.contains("Oldest"))
        XCTAssertFalse(output.contains("OtherApp"))
    }

    func testListReviewsNoCachedReviews() async throws {
        try await storage.save(
            AppModel(id: "app1", name: "Alpha", bundleId: "com.a", accountId: "acc"),
            id: "app1"
        )
        let tool = ListReviewsTool(resolver: resolver, storage: storage)

        let output = await tool.run(appName: "Alpha", limit: 5)

        XCTAssertTrue(output.localizedCaseInsensitiveContains("No reviews"))
    }

    func testListReviewsNoAppMatch() async throws {
        let tool = ListReviewsTool(resolver: resolver, storage: storage)

        let output = await tool.run(appName: "Ghost", limit: 5)

        XCTAssertTrue(output.localizedCaseInsensitiveContains("No app matches"))
    }

    func testListReviewsDisambiguatesMultipleMatches() async throws {
        try await storage.save(
            AppModel(id: "1", name: "Photo One", bundleId: "com.p1", accountId: "acc"),
            id: "1"
        )
        try await storage.save(
            AppModel(id: "2", name: "Photo Two", bundleId: "com.p2", accountId: "acc"),
            id: "2"
        )
        let tool = ListReviewsTool(resolver: resolver, storage: storage)

        let output = await tool.run(appName: "Photo", limit: 5)

        XCTAssertTrue(output.localizedCaseInsensitiveContains("Multiple apps match"))
    }

    func testListReviewsRespectsPermission() async throws {
        var rules = AccountRules.allPermissions
        rules.review = []
        let account = AccountModel(
            id: "acc",
            name: "Account",
            providerType: .apple,
            rules: rules,
            origin: .imported // imported accounts keep their (empty) review rule
        )
        try await storage.save(account, id: "acc")
        try await storage.save(
            AppModel(id: "app1", name: "Alpha", bundleId: "com.a", accountId: "acc"),
            id: "app1"
        )
        try await storage.save(
            review(id: "r", rating: 5, appId: "app1", date: Date(timeIntervalSince1970: 1), body: "Hidden"),
            id: "review.app1.r"
        )
        let tool = ListReviewsTool(resolver: resolver, storage: storage)

        let output = await tool.run(appName: "Alpha", limit: 5)

        XCTAssertTrue(output.localizedCaseInsensitiveContains("permission"))
        XCTAssertFalse(output.contains("Hidden"))
    }
}
#endif
