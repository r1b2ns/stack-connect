import XCTest
@testable import StackConnect

final class DeepLinkTests: XCTestCase {

    func testRoundTripsAllCases() {
        let cases: [DeepLink] = [
            .home,
            .reviews,
            .app(accountId: "acc-1", appId: "123456"),
            .review(accountId: "acc-1", appId: "123456", reviewId: "rev-789")
        ]
        for link in cases {
            let parsed = DeepLink(url: link.url)
            XCTAssertEqual(parsed, link, "Round-trip failed for \(link)")
        }
    }

    func testParsesKnownURLs() {
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://home")!), .home)
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://reviews")!), .reviews)
        XCTAssertEqual(
            DeepLink(url: URL(string: "stackconnect://app/acc-1/123456")!),
            .app(accountId: "acc-1", appId: "123456")
        )
        XCTAssertEqual(
            DeepLink(url: URL(string: "stackconnect://review/acc-1/123456/rev-789")!),
            .review(accountId: "acc-1", appId: "123456", reviewId: "rev-789")
        )
    }

    func testRejectsForeignSchemeAndIncompletePaths() {
        XCTAssertNil(DeepLink(url: URL(string: "https://home")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://app/only-account")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://review/acc/app")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://unknown")!))
    }

    /// Google Play review ids are opaque composites with a slash and app ids
    /// are package names (plan H7).
    func testRoundTripsGooglePlayIds() {
        let link = DeepLink.review(accountId: "fake.play.northwind", appId: "com.northwind.trailhead",
                                   reviewId: "com.northwind.trailhead/gp:AOqpTO 1")
        XCTAssertEqual(DeepLink(url: link.url), link)
        let app = DeepLink.app(accountId: "play-1", appId: "com.northwind.trailhead")
        XCTAssertEqual(DeepLink(url: app.url), app)
    }
}

/// `app` / `review` links branch on the account's provider (plan S5, H7).
final class DeepLinkResolverTests: XCTestCase {

    private var storage: MockPersistentStorable!
    private let apple = AccountModel(id: "asc", name: "ASC", providerType: .apple)
    private let play = AccountModel(id: "play", name: "Play", providerType: .googlePlay)
    private let item = GooglePlayAppItem(id: "com.t", packageName: "com.t", title: "Trailhead", isManuallyAdded: false)

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
        try await storage.save(apple, id: apple.id)
        try await storage.save(play, id: play.id)
        try await storage.save([item], id: GooglePlayAppItem.cacheKey(accountId: play.id))
    }

    private func resolve(_ link: DeepLink) async -> DeepLinkDestination? {
        await DeepLinkResolver(storage: storage).resolve(link)
    }

    func testAppLinkOfAGooglePlayAccountOpensThePlayApp() async {
        let destination = await resolve(.app(accountId: play.id, appId: "com.t"))
        XCTAssertEqual(destination, .googlePlayApp(item, account: play))
    }

    func testAppLinkOfAnAppStoreAccountOpensTheAppStoreApp() async throws {
        let app = AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: apple.id)
        try await storage.save(app, id: "\(apple.id).1")
        let destination = await resolve(.app(accountId: apple.id, appId: "1"))
        XCTAssertEqual(destination, .appStoreApp(app, account: apple))
    }

    func testReviewLinkOfAGooglePlayAccountCarriesThePackage() async throws {
        var review = CustomerReviewModel(id: "com.t/r1", rating: 2)
        review.appId = "com.t"
        try await storage.save(review, id: CustomerReviewModel.storageId(appId: "com.t", reviewId: review.id))

        let destination = await resolve(.review(accountId: play.id, appId: "com.t", reviewId: "com.t/r1"))

        XCTAssertEqual(destination, .review(review, appName: "Trailhead", account: play, appId: "com.t"))
    }

    func testUnknownAccountOrAppResolvesToNothing() async {
        let missingAccount = await resolve(.app(accountId: "gone", appId: "com.t"))
        let missingApp = await resolve(.app(accountId: play.id, appId: "com.other"))
        XCTAssertNil(missingAccount)
        XCTAssertNil(missingApp)
    }
}
