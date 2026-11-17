import XCTest
import StackCoreRust
@testable import StackConnect

/// The App Store side of the reviews provider seam, over a mock connection.
/// It must keep the behaviour the review screens had before the seam.
final class AppleCustomerReviewsServiceTests: XCTestCase {

    private var connection: MockAppleReviewsConnection!
    private var sut: AppleCustomerReviewsService!

    override func setUp() {
        super.setUp()
        connection = MockAppleReviewsConnection()
        sut = AppleCustomerReviewsService(connection: connection)
    }

    override func tearDown() {
        sut = nil
        connection = nil
        super.tearDown()
    }

    func testTraitsAreTheAppStores() {
        XCTAssertEqual(sut.traits, .appStore)
        XCTAssertEqual(sut.traits.sortOptions, ReviewSortOption.allCases)
        XCTAssertTrue(sut.traits.canDeleteReplies)
        XCTAssertTrue(sut.traits.showsStoreRatingSummary)
        XCTAssertNil(sut.traits.replyCharacterLimit)
    }

    // MARK: - Paging

    func testFetchPassesSortFilterLimitAndTokenThrough() async throws {
        connection.pageHandler = {
            AppleAccountConnection.CustomerReviewsPage(
                reviews: [CustomerReviewModel(id: "asc-1", rating: 1)],
                hasNextPage: true,
                rawResponse: "next-token"
            )
        }

        let page = try await sut.fetchReviewsPage(appId: "123", sort: .lowestRating, filterRating: 1, limit: 50, pageToken: "token-1")

        XCTAssertEqual(connection.calls, [
            .fetchPage(appId: "123", sort: "rating", filterRating: ["1"], limit: 50, pageToken: "token-1")
        ])
        XCTAssertEqual(page.reviews.map(\.id), ["asc-1"])
        XCTAssertEqual(page.nextPageToken, "next-token", "The core's nextToken is the opaque page token")
    }

    func testFirstPageWithoutFilterAndLastPageHasNoToken() async throws {
        let page = try await sut.fetchReviewsPage(appId: "123", sort: .newest, filterRating: nil, limit: 50, pageToken: nil)

        XCTAssertEqual(connection.calls, [
            .fetchPage(appId: "123", sort: "-createdDate", filterRating: nil, limit: 50, pageToken: nil)
        ])
        XCTAssertNil(page.nextPageToken)
        XCTAssertFalse(page.hasNextPage)
    }

    func testNonStringRawResponseIsNotAPageToken() async throws {
        connection.pageHandler = {
            AppleAccountConnection.CustomerReviewsPage(reviews: [], hasNextPage: true, rawResponse: 42)
        }

        let page = try await sut.fetchReviewsPage(appId: "123", sort: .newest, filterRating: nil, limit: 50, pageToken: nil)

        XCTAssertNil(page.nextPageToken)
    }

    // MARK: - Replies

    func testNewReplyCreatesWithoutDeleting() async throws {
        let response = try await sut.reply(toReviewId: "asc-1", body: "Thanks!", replacingResponseId: nil)

        XCTAssertEqual(connection.calls, [.reply(reviewId: "asc-1", body: "Thanks!")])
        XCTAssertEqual(response.id, "resp-new")
    }

    /// App Store Connect has no PATCH for replies: editing deletes the existing
    /// response first, then creates the new one.
    func testEditDeletesTheExistingResponseBeforeCreatingTheNewOne() async throws {
        _ = try await sut.reply(toReviewId: "asc-1", body: "Updated", replacingResponseId: "resp-old")

        XCTAssertEqual(connection.calls, [
            .deleteResponse(responseId: "resp-old"),
            .reply(reviewId: "asc-1", body: "Updated")
        ])
    }

    func testEditCreatesNothingWhenTheDeleteFails() async {
        connection.deleteError = StackError.Http(status: 409, message: "")

        do {
            _ = try await sut.reply(toReviewId: "asc-1", body: "Updated", replacingResponseId: "resp-old")
            XCTFail("Expected the delete error")
        } catch {
            XCTAssertEqual(connection.calls, [.deleteResponse(responseId: "resp-old")], "No create after a failed delete")
        }
    }

    /// A fresh response waits for Apple's moderation: "Pending" now, even when
    /// the API leaves the body, state or date out.
    func testMissingResponseFieldsFallBackToPendingNowAndTheSentBody() async throws {
        connection.replyHandler = { _, _ in
            CustomerReviewResponseModel(id: "resp-1", body: nil, state: nil, date: nil)
        }
        let before = Date()

        let response = try await sut.reply(toReviewId: "asc-1", body: "Thanks!", replacingResponseId: nil)

        XCTAssertEqual(response.id, "resp-1")
        XCTAssertEqual(response.body, "Thanks!")
        XCTAssertEqual(response.state, "PENDING_PUBLISH")
        let date = try XCTUnwrap(response.date)
        XCTAssertGreaterThanOrEqual(date, before)
        XCTAssertLessThanOrEqual(date, Date())
    }

    func testReturnedResponseFieldsWin() async throws {
        let published = Date(timeIntervalSince1970: 1_600_000_000)
        connection.replyHandler = { _, _ in
            CustomerReviewResponseModel(id: "resp-1", body: "Stored text", state: "PUBLISHED", date: published)
        }

        let response = try await sut.reply(toReviewId: "asc-1", body: "Sent text", replacingResponseId: nil)

        XCTAssertEqual(response, CustomerReviewResponseModel(id: "resp-1", body: "Stored text", state: "PUBLISHED", date: published))
    }

    func testDeleteReplyDeletesTheResponse() async throws {
        try await sut.deleteReply(responseId: "resp-1")

        XCTAssertEqual(connection.calls, [.deleteResponse(responseId: "resp-1")])
    }

    // MARK: - Error copy

    func testErrorCopyMatchesTheScreensBeforeTheSeam() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Boom"])

        XCTAssertEqual(sut.message(for: error, operation: .load), "Boom")
        XCTAssertEqual(sut.message(for: error, operation: .reply), String(localized: "Failed to send reply"))
        XCTAssertEqual(sut.message(for: error, operation: .deleteReply), String(localized: "Failed to delete reply"))
    }
}

/// Which reviews backend (and cache) each account gets.
@MainActor
final class CustomerReviewsServiceFactoryTests: XCTestCase {

    private var keychain: MockKeyStorable!

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeyStorable()
    }

    override func tearDown() async throws {
        keychain = nil
        try await super.tearDown()
    }

    func testAppleAccountWithCredentialsGetsTheAppStoreService() {
        let account = AccountModel(name: "Team", providerType: .apple)
        keychain.setObject(AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "key"), forKey: "credentials.\(account.id)")

        let service = CustomerReviewsServiceFactory.makeService(for: account, keychain: keychain)

        XCTAssertTrue(service is AppleCustomerReviewsService)
        XCTAssertEqual(service?.traits, .appStore)
    }

    func testPlayAccountWithCredentialsGetsThePlayService() {
        let account = AccountModel(name: "Play Team", providerType: .googlePlay)
        keychain.setObject(
            GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            forKey: "credentials.\(account.id)"
        )

        let service = CustomerReviewsServiceFactory.makeService(for: account, keychain: keychain)

        XCTAssertTrue(service is GooglePlayCustomerReviewsService)
        XCTAssertEqual(service?.traits, .googlePlay)
    }

    func testFirebaseHasNoReviews() {
        let account = AccountModel(name: "Firebase", providerType: .firebase)

        XCTAssertNil(CustomerReviewsServiceFactory.makeService(for: account, keychain: keychain))
    }

    func testMissingCredentialsGiveNoService() {
        XCTAssertNil(CustomerReviewsServiceFactory.makeService(for: AccountModel(name: "Team", providerType: .apple), keychain: keychain))
        XCTAssertNil(CustomerReviewsServiceFactory.makeService(for: AccountModel(name: "Play", providerType: .googlePlay), keychain: keychain))
    }

    func testCredentialsOfTheOtherProviderGiveNoService() {
        let account = AccountModel(name: "Play Team", providerType: .googlePlay)
        keychain.setObject(AppleCredentials(issuerID: "issuer", privateKeyID: "kid", privateKey: "key"), forKey: "credentials.\(account.id)")

        XCTAssertNil(CustomerReviewsServiceFactory.makeService(for: account, keychain: keychain))
    }

    /// Only Google Play reviews are cached by the review screens.
    func testOnlyPlayGetsAReviewsCacheScopedToAccountAndPackage() async {
        let storage = MockPersistentStorable()
        let play = AccountModel(name: "Play Team", providerType: .googlePlay)

        XCTAssertNil(CustomerReviewsServiceFactory.makeCache(for: AccountModel(name: "Team", providerType: .apple), appId: "123", storage: storage))
        XCTAssertNil(CustomerReviewsServiceFactory.makeCache(for: AccountModel(name: "Firebase", providerType: .firebase), appId: "x", storage: storage))

        let cache = CustomerReviewsServiceFactory.makeCache(for: play, appId: "com.example.app", storage: storage)
        let playCache = try? XCTUnwrap(cache as? GooglePlayCustomerReviewsCache)
        XCTAssertEqual(playCache?.store.accountId, play.id)
        XCTAssertEqual(playCache?.store.packageName, "com.example.app")

        await cache?.saveReviews([CustomerReviewModel(id: "com.example.app/r1", rating: 5)])
        let stored = await GooglePlayCustomerReviewsCache(storage: storage, accountId: play.id, packageName: "com.example.app").cachedReviews()
        XCTAssertEqual(stored?.map(\.id), ["com.example.app/r1"])
    }
}
