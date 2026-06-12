import XCTest
@testable import StackConnect

@MainActor
final class AllReviewsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var sut: AllReviewsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        sut = AllReviewsViewModel(storage: storage)
    }

    override func tearDown() async throws {
        sut = nil
        storage = nil
        try await super.tearDown()
    }

    func testExcludesArchivedAppsFromReviews() async throws {
        let activeApp = AppModel(
            id: "app1",
            name: "Active App",
            bundleId: "com.active.app",
            accountId: "acc1",
            isArchived: false
        )
        let archivedApp = AppModel(
            id: "app2",
            name: "Archived App",
            bundleId: "com.archived.app",
            accountId: "acc1",
            isArchived: true
        )
        let account = AccountModel(
            id: "acc1",
            name: "Test Account",
            providerType: .apple,
            createdAt: Date(),
            rules: AccountRules()
        )

        try await storage.save(activeApp, id: activeApp.id)
        try await storage.save(archivedApp, id: archivedApp.id)
        try await storage.save(account, id: account.id)

        var activeReview = CustomerReviewModel(
            id: "rev1",
            rating: 5,
            title: "Great app",
            body: "Very good",
            createdDate: Date()
        )
        activeReview.appId = "app1"

        var archivedReview = CustomerReviewModel(
            id: "rev2",
            rating: 3,
            title: "Was okay",
            body: "Not bad",
            createdDate: Date()
        )
        archivedReview.appId = "app2"

        try await storage.save(activeReview, id: activeReview.id)
        try await storage.save(archivedReview, id: archivedReview.id)

        await sut.load()

        XCTAssertEqual(sut.uiState.groups.count, 1)
        XCTAssertEqual(sut.uiState.groups.first?.app.id, "app1")
        XCTAssertEqual(sut.uiState.groups.first?.reviews.count, 1)
    }

    func testHandlesEmptyReviews() async throws {
        let app = AppModel(
            id: "app1",
            name: "Test App",
            bundleId: "com.test.app",
            accountId: "acc1",
            isArchived: false
        )
        let account = AccountModel(
            id: "acc1",
            name: "Test Account",
            providerType: .apple,
            createdAt: Date(),
            rules: AccountRules()
        )

        try await storage.save(app, id: app.id)
        try await storage.save(account, id: account.id)

        await sut.load()

        XCTAssertTrue(sut.uiState.groups.isEmpty)
    }

    func testHandlesAllArchivedApps() async throws {
        let archivedApp1 = AppModel(
            id: "app1",
            name: "Archived App 1",
            bundleId: "com.archived1.app",
            accountId: "acc1",
            isArchived: true
        )
        let archivedApp2 = AppModel(
            id: "app2",
            name: "Archived App 2",
            bundleId: "com.archived2.app",
            accountId: "acc1",
            isArchived: true
        )
        let account = AccountModel(
            id: "acc1",
            name: "Test Account",
            providerType: .apple,
            createdAt: Date(),
            rules: AccountRules()
        )

        try await storage.save(archivedApp1, id: archivedApp1.id)
        try await storage.save(archivedApp2, id: archivedApp2.id)
        try await storage.save(account, id: account.id)

        var review1 = CustomerReviewModel(
            id: "rev1",
            rating: 4,
            title: "Good",
            body: "Nice",
            createdDate: Date()
        )
        review1.appId = "app1"

        var review2 = CustomerReviewModel(
            id: "rev2",
            rating: 5,
            title: "Excellent",
            body: "Amazing",
            createdDate: Date()
        )
        review2.appId = "app2"

        try await storage.save(review1, id: review1.id)
        try await storage.save(review2, id: review2.id)

        await sut.load()

        XCTAssertTrue(sut.uiState.isEmpty)
    }
}
