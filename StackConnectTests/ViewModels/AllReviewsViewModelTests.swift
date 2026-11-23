import XCTest
@testable import StackConnect

@MainActor
final class AllReviewsViewModelTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private var sut: AllReviewsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        sut = AllReviewsViewModel(storage: storage, featureFlags: .googlePlayOn)
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
        XCTAssertEqual(sut.uiState.groups.first?.appId, "app1")
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

    // MARK: - Both stores (plan S4)

    func testGroupsAppStoreAndGooglePlayReviewsByApp() async throws {
        let apple = AccountModel(id: "asc", name: "ASC", providerType: .apple)
        let play = AccountModel(id: "play", name: "Play", providerType: .googlePlay)
        try await storage.save(apple, id: apple.id)
        try await storage.save(play, id: play.id)
        let app = AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", platform: "IOS", accountId: apple.id)
        try await storage.save(app, id: "\(apple.id).1")
        try await storage.save([GooglePlayAppItem(id: "com.t", packageName: "com.t", title: "Trailhead", isManuallyAdded: false)],
                               id: GooglePlayAppItem.cacheKey(accountId: play.id))
        try await saveReview("a1", appId: "1", hoursAgo: 3)
        try await saveReview("com.t/1", appId: "com.t", hoursAgo: 1)
        try await saveReview("com.t/2", appId: "com.t", hoursAgo: 5)

        await sut.load()

        XCTAssertEqual(sut.uiState.groups.map(\.appName), ["Trailhead", "Pulse"])
        XCTAssertEqual(sut.uiState.groups.first?.reviews.map(\.review.id), ["com.t/1", "com.t/2"])
        XCTAssertEqual(sut.uiState.groups.first?.target, .googlePlay(GooglePlayAppItem(id: "com.t", packageName: "com.t", title: "Trailhead", isManuallyAdded: false)))
        XCTAssertEqual(sut.uiState.groups.first?.account, play)
    }

    func testHidesGooglePlayReviewsAndFilterWhileGooglePlayIsHidden() async throws {
        let hidden = AllReviewsViewModel(storage: storage, featureFlags: .googlePlayOff)
        let apple = AccountModel(id: "asc", name: "ASC", providerType: .apple)
        let play = AccountModel(id: "play", name: "Play", providerType: .googlePlay)
        try await storage.save(apple, id: apple.id)
        try await storage.save(play, id: play.id)
        try await storage.save(AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", platform: "IOS", accountId: apple.id), id: "\(apple.id).1")
        try await storage.save([GooglePlayAppItem(id: "com.t", packageName: "com.t", title: "Trailhead", isManuallyAdded: false)],
                               id: GooglePlayAppItem.cacheKey(accountId: play.id))
        try await saveReview("a1", appId: "1", hoursAgo: 3)
        try await saveReview("com.t/1", appId: "com.t", hoursAgo: 1)

        await hidden.load()
        hidden.applyFilter(.googlePlay)

        XCTAssertEqual(hidden.uiState.groups.map(\.appName), ["Pulse"])
        XCTAssertEqual(hidden.uiState.availableFilters, [.all, .appStore, .unreplied])
        XCTAssertEqual(hidden.uiState.filter, .all, "A hidden filter can't be picked")
        XCTAssertEqual(sut.uiState.availableFilters, AllReviewsFilter.allCases, "Flag ON offers every filter")
    }

    func testSamePackageUnderTwoPlayAccountsIsOneGroup() async throws {
        for id in ["play-a", "play-b"] {
            try await storage.save(AccountModel(id: id, name: id, providerType: .googlePlay), id: id)
            try await storage.save([GooglePlayAppItem(id: "com.t", packageName: "com.t", title: "Trailhead", isManuallyAdded: false)],
                                   id: GooglePlayAppItem.cacheKey(accountId: id))
        }
        try await saveReview("com.t/1", appId: "com.t", hoursAgo: 1)

        await sut.load()

        XCTAssertEqual(sut.uiState.groups.count, 1)
        XCTAssertEqual(sut.uiState.groups.first?.reviews.count, 1)
    }

    /// The same App Store app under two accounts used to crash
    /// `Dictionary(uniqueKeysWithValues:)`.
    func testDuplicateAppIdDoesNotCrash() async throws {
        for id in ["asc-a", "asc-b"] {
            try await storage.save(AccountModel(id: id, name: id, providerType: .apple), id: id)
            let app = AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: id)
            try await storage.save(app, id: "\(id).1")
        }
        try await saveReview("a1", appId: "1", hoursAgo: 1)

        await sut.load()

        XCTAssertEqual(sut.uiState.groups.count, 1)
        XCTAssertEqual(sut.uiState.groups.first?.reviews.map(\.review.id), ["a1"])
    }

    private func saveReview(_ id: String, appId: String, hoursAgo: Double) async throws {
        var review = CustomerReviewModel(id: id, rating: 4, body: "Body", createdDate: Date().addingTimeInterval(-hoursAgo * 3600))
        review.appId = appId
        try await storage.save(review, id: CustomerReviewModel.storageId(appId: appId, reviewId: id))
    }
}
