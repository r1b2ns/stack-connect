import XCTest
import StackProtocols
import StackHomeCore
@testable import WindowsAppCore

/// Proves that `AppleConnectionProtocol` is mockable, injectable, and that
/// every method on the protocol surface is callable through the mock.
/// This validates AC-2 (mockable protocol) and AC-5 (mock available for tests)
/// of task T-W01.
@MainActor
final class AppleConnectionProtocolTests: XCTestCase {

    private var connection: MockAppleConnection!

    override func setUp() {
        super.setUp()
        connection = MockAppleConnection()
    }

    override func tearDown() {
        connection = nil
        super.tearDown()
    }

    // MARK: - validateCredentials

    func testValidateCredentials_success() async throws {
        connection.validateCredentialsResult = .success(())

        try await connection.validateCredentials()

        XCTAssertEqual(connection.validateCredentialsCallCount, 1)
    }

    func testValidateCredentials_failure() async {
        let expectedError = NSError(domain: "test", code: 401)
        connection.validateCredentialsResult = .failure(expectedError)

        do {
            try await connection.validateCredentials()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).code, 401)
        }
        XCTAssertEqual(connection.validateCredentialsCallCount, 1)
    }

    // MARK: - fetchApps

    func testFetchApps_returnsCannedApps() async throws {
        let apps = [
            AppInfo(id: "1", name: "App One", bundleId: "com.one"),
            AppInfo(id: "2", name: "App Two", bundleId: "com.two"),
        ]
        connection.fetchAppsResult = .success(apps)

        let result = try await connection.fetchApps()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.name, "App One")
        XCTAssertEqual(connection.fetchAppsCallCount, 1)
    }

    // MARK: - fetchUsers

    func testFetchUsers_returnsCannedUsers() async throws {
        let users = [
            UserModel(id: "u1", firstName: "Alice", lastName: "Smith", email: "alice@example.com", roles: ["ADMIN"]),
            UserModel(id: "u2", firstName: "Bob", isPending: true),
        ]
        connection.fetchUsersResult = .success(users)

        let result = try await connection.fetchUsers()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].displayName, "Alice Smith")
        XCTAssertTrue(result[1].isPending)
        XCTAssertEqual(connection.fetchUsersCallCount, 1)
    }

    // MARK: - fetchReviews (paginated)

    func testFetchReviews_firstPage() async throws {
        let reviews = [
            CustomerReviewModel(id: "r1", rating: 5, title: "Great", body: "Love it"),
            CustomerReviewModel(id: "r2", rating: 1, title: "Bad", body: "Crashes"),
        ]
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: reviews, hasNextPage: true, cursor: "next-token")
        )

        let page = try await connection.fetchReviews(appId: "app-123")

        XCTAssertEqual(page.reviews.count, 2)
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.cursor, "next-token")
        XCTAssertEqual(connection.fetchReviewsCallCount, 1)
        XCTAssertEqual(connection.lastFetchReviewsAppId, "app-123")
        XCTAssertEqual(connection.lastFetchReviewsSort, .createdDateDescending)
        XCTAssertNil(connection.lastFetchReviewsFilterRating)
        XCTAssertEqual(connection.lastFetchReviewsLimit, 50)
        XCTAssertNil(connection.lastFetchReviewsCursor)
    }

    func testFetchReviews_nextPage_passesCursorAndSort() async throws {
        connection.fetchReviewsResult = .success(
            ReviewsPage(reviews: [], hasNextPage: false, cursor: nil)
        )

        _ = try await connection.fetchReviews(
            appId: "app-123",
            sort: .ratingAscending,
            filterRating: ["1", "2"],
            limit: 20,
            cursor: "page-2-cursor"
        )

        XCTAssertEqual(connection.lastFetchReviewsCursor, "page-2-cursor")
        XCTAssertEqual(connection.lastFetchReviewsSort, .ratingAscending)
        XCTAssertEqual(connection.lastFetchReviewsFilterRating, ["1", "2"])
        XCTAssertEqual(connection.lastFetchReviewsLimit, 20)
    }

    // MARK: - upsertReply (create path — existingResponseId is nil)

    func testUpsertReply_create_capturesArguments() async throws {
        connection.upsertReplyResult = .success(())

        try await connection.upsertReply(
            reviewId: "r1",
            existingResponseId: nil,
            responseBody: "Thank you!"
        )

        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertEqual(connection.lastUpsertReplyReviewId, "r1")
        XCTAssertNil(connection.lastUpsertReplyExistingResponseId)
        XCTAssertEqual(connection.lastUpsertReplyBody, "Thank you!")
    }

    // MARK: - upsertReply (update path — existingResponseId is non-nil)

    func testUpsertReply_update_capturesExistingResponseId() async throws {
        connection.upsertReplyResult = .success(())

        try await connection.upsertReply(
            reviewId: "r1",
            existingResponseId: "resp-42",
            responseBody: "Updated reply"
        )

        XCTAssertEqual(connection.upsertReplyCallCount, 1)
        XCTAssertEqual(connection.lastUpsertReplyReviewId, "r1")
        XCTAssertEqual(connection.lastUpsertReplyExistingResponseId, "resp-42")
        XCTAssertEqual(connection.lastUpsertReplyBody, "Updated reply")
    }

    // MARK: - upsertReply (error path)

    func testUpsertReply_propagatesError() async {
        let expectedError = NSError(domain: "test", code: 500)
        connection.upsertReplyResult = .failure(expectedError)

        do {
            try await connection.upsertReply(
                reviewId: "r1",
                existingResponseId: nil,
                responseBody: "Thanks"
            )
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).code, 500)
        }
    }

    // MARK: - deleteReply

    func testDeleteReply_capturesResponseId() async throws {
        connection.deleteReplyResult = .success(())

        try await connection.deleteReply(responseId: "resp-42")

        XCTAssertEqual(connection.deleteReplyCallCount, 1)
        XCTAssertEqual(connection.lastDeleteReplyResponseId, "resp-42")
    }

    func testDeleteReply_propagatesError() async {
        let expectedError = NSError(domain: "test", code: 404)
        connection.deleteReplyResult = .failure(expectedError)

        do {
            try await connection.deleteReply(responseId: "resp-99")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).code, 404)
        }
    }

    // MARK: - Injection (proves DI works with any conformance)

    func testProtocolIsInjectableAsTypeErasedDependency() async throws {
        // Proves a function / ViewModel can accept any AppleConnectionProtocol
        let injected: any AppleConnectionProtocol = connection
        let apps = try await injected.fetchApps()
        XCTAssertEqual(apps.count, 0)
    }
}
