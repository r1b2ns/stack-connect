import XCTest
@testable import StackConnect

final class DeepLinkTests: XCTestCase {

    func testRoundTripsAllCases() {
        let cases: [DeepLink] = [
            .home,
            .reviews,
            .networkAudit,
            .testFlight,
            .remoteConfig,
            .certificates,
            .app(accountId: "acc-1", appId: "123456"),
            .review(accountId: "acc-1", appId: "123456", reviewId: "rev-789"),
            .reimport(accountId: "acc-1")
        ]
        for link in cases {
            let parsed = DeepLink(url: link.url)
            XCTAssertEqual(parsed, link, "Round-trip failed for \(link)")
        }
    }

    func testParsesKnownURLs() {
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://home")!), .home)
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://reviews")!), .reviews)
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://network-audit")!), .networkAudit)
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

    /// The App Store In-App Event link: the exact URL is part of the event's
    /// metadata, so it must never change.
    func testNetworkAuditURLIsStable() {
        XCTAssertEqual(DeepLink.networkAudit.url.absoluteString, "stackconnect://network-audit")
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://network-audit?source=widget")!), .networkAudit,
                       "Query items don't change the route")
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://networkaudit")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://network_audit")!))
    }

    /// App Store custom product pages and In-App Events carry these exact
    /// URLs in their metadata, so they must never change.
    func testEntryPointURLsAreStable() {
        XCTAssertEqual(DeepLink.testFlight.url.absoluteString, "stackconnect://testflight")
        XCTAssertEqual(DeepLink.remoteConfig.url.absoluteString, "stackconnect://remote-config")
        XCTAssertEqual(DeepLink.certificates.url.absoluteString, "stackconnect://certificates")
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://testflight")!), .testFlight)
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://remote-config?source=widget")!), .remoteConfig,
                       "Query items don't change the route")
        XCTAssertEqual(DeepLink(url: URL(string: "stackconnect://certificates")!), .certificates)
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://test-flight")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://remoteconfig")!))
        XCTAssertNil(DeepLink(url: URL(string: "stackconnect://remote_config")!))
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
        await DeepLinkResolver(storage: storage, featureFlags: .googlePlayOn).resolve(link)
    }

    func testGooglePlayLinksResolveToNothingWhileGooglePlayIsHidden() async throws {
        let resolver = DeepLinkResolver(storage: storage, featureFlags: .googlePlayOff)
        var review = CustomerReviewModel(id: "com.t/r1", rating: 4)
        review.appId = "com.t"
        try await storage.save(review, id: CustomerReviewModel.storageId(appId: "com.t", reviewId: review.id))

        let app = await resolver.resolve(.app(accountId: play.id, appId: "com.t"))
        let reviewDestination = await resolver.resolve(.review(accountId: play.id, appId: "com.t", reviewId: review.id))

        XCTAssertNil(app)
        XCTAssertNil(reviewDestination)
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

/// `testflight`, `remote-config` and `certificates` carry no account: the
/// landing depends on what the user has.
final class DeepLinkLandingTests: XCTestCase {

    private var storage: MockPersistentStorable!

    override func setUp() async throws {
        try await super.setUp()
        storage = MockPersistentStorable()
    }

    private func landing(_ link: DeepLink, flags: FeatureFlags = .googlePlayOff) async -> DeepLinkLanding? {
        await DeepLinkResolver(storage: storage, featureFlags: flags).landing(for: link)
    }

    private func save(_ account: AccountModel) async throws {
        try await storage.save(account, id: account.id)
    }

    private func save(_ app: AppModel) async throws {
        try await storage.save(app, id: "\(app.accountId).\(app.id)")
    }

    // MARK: - No accounts

    func testEveryEntryPointOpensTheHomeWithoutAccounts() async {
        let testFlight = await landing(.testFlight)
        let remoteConfig = await landing(.remoteConfig)
        let certificates = await landing(.certificates)
        XCTAssertEqual(testFlight, .home)
        XCTAssertEqual(remoteConfig, .home)
        XCTAssertEqual(certificates, .home)
    }

    func testAccountsOfAnotherStoreDontCount() async throws {
        try await save(AccountModel(id: "fb", name: "Firebase", providerType: .firebase))
        let testFlight = await landing(.testFlight)
        let certificates = await landing(.certificates)
        XCTAssertEqual(testFlight, .home, "A Firebase account has no TestFlight")
        XCTAssertEqual(certificates, .home)
    }

    func testHiddenGooglePlayAccountsDontCountForAnything() async throws {
        try await save(AccountModel(id: "play", name: "Play", providerType: .googlePlay))
        let testFlight = await landing(.testFlight, flags: .googlePlayOff)
        XCTAssertEqual(testFlight, .home)
    }

    func testOtherLinksHaveNoLanding() async {
        let home = await landing(.home)
        let app = await landing(.app(accountId: "a", appId: "b"))
        XCTAssertNil(home)
        XCTAssertNil(app)
    }

    // MARK: - TestFlight

    func testTestFlightOpensTheOnlyAppDirectly() async throws {
        let account = AccountModel(id: "asc", name: "ASC", providerType: .apple)
        let app = AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: account.id)
        try await save(account)
        try await save(app)

        let destination = await landing(.testFlight)

        XCTAssertEqual(destination, .testFlight(app, account: account))
    }

    func testTestFlightOpensTheAppListOfTheOnlyAccountWithSeveralApps() async throws {
        let account = AccountModel(id: "asc", name: "ASC", providerType: .apple)
        try await save(account)
        try await save(AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: account.id))
        try await save(AppModel(id: "2", name: "Trail", bundleId: "com.trail", accountId: account.id))

        let destination = await landing(.testFlight)

        XCTAssertEqual(destination, .accountSection(account, .apps))
    }

    func testTestFlightOpensTheAppListOfTheOnlyAccountBeforeItsFirstSync() async throws {
        let account = AccountModel(id: "asc", name: "ASC", providerType: .apple)
        try await save(account)

        let destination = await landing(.testFlight)

        XCTAssertEqual(destination, .accountSection(account, .apps))
    }

    func testTestFlightIgnoresArchivedAndOutOfScopeApps() async throws {
        let account = AccountModel(id: "asc", name: "ASC", providerType: .apple, appsBundles: ["com.pulse", "com.old"])
        let pulse = AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: account.id)
        try await save(account)
        try await save(pulse)
        try await save(AppModel(id: "2", name: "Old", bundleId: "com.old", accountId: account.id, isArchived: true))
        try await save(AppModel(id: "3", name: "Other", bundleId: "com.other", accountId: account.id))

        let destination = await landing(.testFlight)

        XCTAssertEqual(destination, .testFlight(pulse, account: account))
    }

    func testTestFlightOpensTheOnlyAppEvenAcrossAccounts() async throws {
        let first = AccountModel(id: "asc-1", name: "One", providerType: .apple)
        let second = AccountModel(id: "asc-2", name: "Two", providerType: .apple)
        let app = AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: second.id)
        try await save(first)
        try await save(second)
        try await save(app)

        let destination = await landing(.testFlight)

        XCTAssertEqual(destination, .testFlight(app, account: second))
    }

    func testTestFlightOpensTheAccountChooserWithSeveralAccountsAndApps() async throws {
        let first = AccountModel(id: "asc-1", name: "One", providerType: .apple)
        let second = AccountModel(id: "asc-2", name: "Two", providerType: .apple)
        try await save(first)
        try await save(second)
        try await save(AppModel(id: "1", name: "Pulse", bundleId: "com.pulse", accountId: first.id))
        try await save(AppModel(id: "2", name: "Trail", bundleId: "com.trail", accountId: second.id))

        let destination = await landing(.testFlight)

        XCTAssertEqual(destination, .accountChooser)
    }

    func testTestFlightSkipsExpiredAndForbiddenAccounts() async throws {
        let expired = AccountModel(id: "asc-1", name: "Expired", providerType: .apple, expirationDate: .distantPast)
        let noTestFlight = AccountModel(id: "asc-2", name: "Sales", providerType: .apple,
                                        rules: AccountRules(apps: [.view]), origin: .imported)
        let usable = AccountModel(id: "asc-3", name: "Dev", providerType: .apple)
        try await save(expired)
        try await save(noTestFlight)
        try await save(usable)
        try await save(AppModel(id: "1", name: "Old", bundleId: "com.old", accountId: expired.id))
        try await save(AppModel(id: "2", name: "Sales", bundleId: "com.sales", accountId: noTestFlight.id))

        let destination = await landing(.testFlight)

        XCTAssertEqual(destination, .accountSection(usable, .apps))
    }

    func testTestFlightOpensTheAccountChooserWhenNoAccountCanOpenIt() async throws {
        try await save(AccountModel(id: "asc", name: "Expired", providerType: .apple, expirationDate: .distantPast))

        let destination = await landing(.testFlight)

        XCTAssertEqual(destination, .accountChooser, "The list shows why the account is locked")
    }

    // MARK: - Remote Config

    func testRemoteConfigOpensTheProjectListOfTheOnlyFirebaseAccount() async throws {
        let account = AccountModel(id: "fb", name: "Firebase", providerType: .firebase)
        try await save(account)

        let destination = await landing(.remoteConfig)

        XCTAssertEqual(destination, .accountSection(account, .apps))
    }

    func testRemoteConfigOpensTheProjectOfAnAccountScopedToOne() async throws {
        let account = AccountModel(id: "fb", name: "Firebase", providerType: .firebase,
                                   appsBundles: ["pulse-prod"], authMethod: .googleSignIn)
        try await save(account)

        let destination = await landing(.remoteConfig)

        guard case let .remoteConfig(project, landedAccount) = destination else {
            return XCTFail("Expected the project's Remote Config, got \(String(describing: destination))")
        }
        XCTAssertEqual(project.projectId, "pulse-prod")
        XCTAssertEqual(landedAccount, account)
    }

    func testRemoteConfigOpensTheAccountChooserWithSeveralFirebaseAccounts() async throws {
        try await save(AccountModel(id: "fb-1", name: "One", providerType: .firebase, appsBundles: ["a"]))
        try await save(AccountModel(id: "fb-2", name: "Two", providerType: .firebase))

        let destination = await landing(.remoteConfig)

        XCTAssertEqual(destination, .accountChooser)
    }

    // MARK: - Certificates

    func testCertificatesOpenTheListOfTheOnlyAccountAllowedToSeeThem() async throws {
        let provisioning = AccountModel(id: "asc-1", name: "Dev", providerType: .apple)
        let sales = AccountModel(id: "asc-2", name: "Sales", providerType: .apple,
                                 rules: AccountRules(apps: [.view]), origin: .imported)
        try await save(provisioning)
        try await save(sales)

        let destination = await landing(.certificates)

        XCTAssertEqual(destination, .accountSection(provisioning, .certificates))
    }

    func testCertificatesOpenTheAccountChooserWithSeveralAccounts() async throws {
        try await save(AccountModel(id: "asc-1", name: "One", providerType: .apple))
        try await save(AccountModel(id: "asc-2", name: "Two", providerType: .apple))

        let destination = await landing(.certificates)

        XCTAssertEqual(destination, .accountChooser)
    }
}
