import XCTest
import StackCoreRust
@testable import StackConnect

/// Phase 3 surface of `GooglePlayAccountConnection`: mapping of the core's app
/// details / store listings / tracks / reviews records onto the app models, and
/// the offline guard + Rust-core routing of the new calls. Nothing reaches
/// Google: calls are either blocked offline or fail inside `connect(...)`.
final class GooglePlayAppContentConnectionTests: XCTestCase {

    private func makeConnection(online: Bool) -> GooglePlayAccountConnection {
        GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(serviceAccountJSON: GooglePlayTestFixtures.serviceAccountJSON()),
            connectivity: MockConnectivityProviding(online: online)
        )
    }

    // MARK: - App details

    func testMapAppDetailsCopiesEveryField() {
        let model = GooglePlayAccountConnection.mapAppDetails(StackCoreRust.AppDetailsInfo(
            appId: "com.example.app",
            defaultLanguage: "en-US",
            contactEmail: "support@example.com",
            contactPhone: "+1 555 0100",
            contactWebsite: "https://example.com"
        ))

        XCTAssertEqual(model, GooglePlayAppDetailsModel(
            packageName: "com.example.app",
            defaultLanguage: "en-US",
            contactEmail: "support@example.com",
            contactPhone: "+1 555 0100",
            contactWebsite: "https://example.com"
        ))
    }

    func testMapAppDetailsKeepsMissingFieldsNil() {
        let model = GooglePlayAccountConnection.mapAppDetails(StackCoreRust.AppDetailsInfo(
            appId: "com.example.app",
            defaultLanguage: nil,
            contactEmail: nil,
            contactPhone: nil,
            contactWebsite: nil
        ))

        XCTAssertEqual(model.packageName, "com.example.app")
        XCTAssertNil(model.defaultLanguage)
        XCTAssertNil(model.contactEmail)
        XCTAssertNil(model.contactPhone)
        XCTAssertNil(model.contactWebsite)
    }

    // MARK: - Store listings

    func testMapStoreListingCopiesEveryField() {
        let model = GooglePlayAccountConnection.mapStoreListing(StackCoreRust.StoreListingInfo(
            language: "pt-BR",
            title: "Meu App",
            shortDescription: "Curta",
            fullDescription: "Completa",
            video: "https://youtu.be/abc"
        ))

        XCTAssertEqual(model.id, "pt-BR")
        XCTAssertEqual(model.language, "pt-BR")
        XCTAssertEqual(model.title, "Meu App")
        XCTAssertEqual(model.shortDescription, "Curta")
        XCTAssertEqual(model.fullDescription, "Completa")
        XCTAssertEqual(model.video, "https://youtu.be/abc")
    }

    // MARK: - Tracks

    func testMapTrackMapsReleasesStatusFractionNotesAndPriority() {
        let model = GooglePlayAccountConnection.mapTrack(StackCoreRust.TrackInfo(
            track: "production",
            releases: [
                StackCoreRust.TrackReleaseInfo(
                    name: "1.4.0",
                    status: "inProgress",
                    versionCodes: ["140", "9223372036854775807"],
                    userFraction: 0.2,
                    releaseNotes: [StackCoreRust.LocalizedTextInfo(language: "en-US", text: "Bug fixes")],
                    inAppUpdatePriority: 3
                ),
                StackCoreRust.TrackReleaseInfo(
                    name: nil,
                    status: "completed",
                    versionCodes: ["130"],
                    userFraction: nil,
                    releaseNotes: [],
                    inAppUpdatePriority: nil
                )
            ]
        ))

        XCTAssertEqual(model.track, "production")
        XCTAssertEqual(model.kind, .production)
        XCTAssertEqual(model.releases.count, 2)

        let rollout = model.releases[0]
        XCTAssertEqual(rollout.name, "1.4.0")
        XCTAssertEqual(rollout.status, .inProgress)
        XCTAssertEqual(rollout.versionCodes, ["140", "9223372036854775807"], "int64 codes stay decimal strings")
        XCTAssertEqual(rollout.userFraction, 0.2)
        XCTAssertEqual(rollout.rolloutFraction, 0.2)
        XCTAssertEqual(rollout.releaseNotes, [GooglePlayLocalizedTextModel(language: "en-US", text: "Bug fixes")])
        XCTAssertEqual(rollout.inAppUpdatePriority, 3)

        let completed = model.releases[1]
        XCTAssertEqual(completed.status, .completed)
        XCTAssertNil(completed.userFraction)
        XCTAssertNil(completed.rolloutFraction)
        XCTAssertNil(completed.inAppUpdatePriority)
        XCTAssertEqual(completed.displayName, "130", "No name falls back to the version codes")
    }

    func testMapReleaseFoldsUnknownAndMissingStatusIntoUnknown() {
        let unspecified = GooglePlayAccountConnection.mapRelease(release(status: "statusUnspecified"))
        let missing = GooglePlayAccountConnection.mapRelease(release(status: nil))
        let halted = GooglePlayAccountConnection.mapRelease(release(status: "halted"))
        let draft = GooglePlayAccountConnection.mapRelease(release(status: "draft"))

        XCTAssertEqual(unspecified.status, .unknown)
        XCTAssertEqual(missing.status, .unknown)
        XCTAssertEqual(halted.status, .halted)
        XCTAssertEqual(draft.status, .draft)
    }

    func testMapTrackKeepsATrackWithoutReleases() {
        let model = GooglePlayAccountConnection.mapTrack(StackCoreRust.TrackInfo(track: "internal", releases: []))

        XCTAssertEqual(model.kind, .internalTesting)
        XCTAssertTrue(model.releases.isEmpty)
    }

    private func release(status: String?) -> StackCoreRust.TrackReleaseInfo {
        StackCoreRust.TrackReleaseInfo(
            name: "r",
            status: status,
            versionCodes: [],
            userFraction: nil,
            releaseNotes: [],
            inAppUpdatePriority: nil
        )
    }

    // MARK: - Reviews

    /// Play review ids are opaque `{packageName}/{reviewId}` composites the core
    /// needs back verbatim: the mapping must neither parse nor rebuild them.
    func testReviewMappingPassesTheCompositeIdThroughAndMapsTheReply() {
        let compositeId = "com.example.app/gp:AOqpTOH_review-1"
        let core = StackCoreRust.CustomerReview(
            id: compositeId,
            rating: 4,
            title: "Nice",
            body: "Works well",
            reviewerNickname: "Ana",
            createdDate: "2026-10-01T12:30:00Z",
            territory: nil,
            response: StackCoreRust.ReviewResponse(
                id: compositeId,
                body: "Thanks, Ana!",
                state: nil,
                lastModifiedDate: "2026-10-02T08:00:00Z"
            )
        )

        let model = CoreReviewMapper.customerReview(core)

        XCTAssertEqual(model.id, compositeId)
        XCTAssertEqual(model.rating, 4)
        XCTAssertEqual(model.title, "Nice")
        XCTAssertEqual(model.body, "Works well")
        XCTAssertEqual(model.reviewerNickname, "Ana")
        XCTAssertEqual(model.createdDate, ISO8601DateFormatter().date(from: "2026-10-01T12:30:00Z"))
        XCTAssertNil(model.territory, "Play has no territory")
        XCTAssertEqual(model.responseId, compositeId, "Play reuses the review id for the reply")
        XCTAssertEqual(model.responseBody, "Thanks, Ana!")
        XCTAssertNil(model.responseState, "Play replies have no state")
        XCTAssertEqual(model.responseDate, ISO8601DateFormatter().date(from: "2026-10-02T08:00:00Z"))
        XCTAssertTrue(model.hasResponse)
    }

    func testReviewPageMappingKeepsTheNextTokenOpaque() {
        let page = CoreReviewMapper.page(StackCoreRust.CustomerReviewsPage(
            reviews: [
                StackCoreRust.CustomerReview(
                    id: "com.example.app/r1", rating: 5, title: nil, body: "Great",
                    reviewerNickname: nil, createdDate: nil, territory: nil, response: nil
                )
            ],
            nextToken: "opaque-token=="
        ))

        XCTAssertEqual(page.reviews.map(\.id), ["com.example.app/r1"])
        XCTAssertEqual(page.nextPageToken, "opaque-token==")
        XCTAssertTrue(page.hasNextPage)
        XCTAssertFalse(page.reviews[0].hasResponse)
    }

    func testReviewResponseMapping() {
        let response = CoreReviewMapper.reviewResponse(StackCoreRust.ReviewResponse(
            id: "com.example.app/r1",
            body: "Thanks!",
            state: nil,
            lastModifiedDate: "2026-10-02T08:00:00.250Z"
        ))

        XCTAssertEqual(response.id, "com.example.app/r1")
        XCTAssertEqual(response.body, "Thanks!")
        XCTAssertNil(response.state)
        XCTAssertNotNil(response.date, "Fractional seconds are parsed too")
    }

    /// App Store reviews carry what Play reviews don't (territory, a separate
    /// response id, a moderation state): the Apple mapping keeps all of it.
    func testAppleReviewMappingKeepsTheAppStoreFields() {
        let core = StackCoreRust.CustomerReview(
            id: "asc-1", rating: 2, title: "Crashes", body: "On launch", reviewerNickname: "Ana",
            createdDate: "2024-01-15T10:30:00Z", territory: "USA",
            response: StackCoreRust.ReviewResponse(id: "resp-9", body: "Fixed in 2.1", state: "PUBLISHED", lastModifiedDate: nil)
        )

        let model = AppleAccountConnection.mapCustomerReview(core)

        XCTAssertEqual(model, CustomerReviewModel(
            id: "asc-1",
            rating: 2,
            title: "Crashes",
            body: "On launch",
            reviewerNickname: "Ana",
            createdDate: ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z"),
            territory: "USA",
            responseId: "resp-9",
            responseBody: "Fixed in 2.1",
            responseState: "PUBLISHED",
            responseDate: nil
        ))
        XCTAssertNil(model.appId, "Only SyncService sets the app id")
    }

    // MARK: - Offline guard (fails fast, before any edit is opened)

    func testEveryNewCallThrowsOfflineErrorWhenOffline() async {
        let connection = makeConnection(online: false)

        await assertOffline { _ = try await connection.fetchAppDetails(packageName: "com.example.app") }
        await assertOffline { _ = try await connection.fetchStoreListings(packageName: "com.example.app") }
        await assertOffline { _ = try await connection.fetchTracks(packageName: "com.example.app") }
        await assertOffline {
            _ = try await connection.fetchCustomerReviewsPage(packageName: "com.example.app", filterRating: nil, limit: 50, pageToken: nil)
        }
        await assertOffline { _ = try await connection.replyToReview(reviewId: "com.example.app/r1", body: "Thanks") }
    }

    // MARK: - Rust core routing (online, but no network reached)

    func testNewCallsRouteThroughTheCoreAndSurfaceItsTypedError() async {
        // The fixture key is not a parseable RSA key: the core rejects it inside
        // `connect`, before any request.
        let connection = makeConnection(online: true)

        await assertInvalidCredentials { _ = try await connection.fetchAppDetails(packageName: "com.example.app") }
        await assertInvalidCredentials { _ = try await connection.fetchStoreListings(packageName: "com.example.app") }
        await assertInvalidCredentials { _ = try await connection.fetchTracks(packageName: "com.example.app") }
        await assertInvalidCredentials {
            _ = try await connection.fetchCustomerReviewsPage(packageName: "com.example.app", filterRating: 5, limit: 500, pageToken: nil)
        }
        await assertInvalidCredentials { _ = try await connection.replyToReview(reviewId: "com.example.app/r1", body: "Thanks") }
    }

    func testReviewsUseGooglesOnlySortOrderAndClampThePageSize() {
        XCTAssertEqual(GooglePlayAccountConnection.reviewsSort, "-createdDate")
        XCTAssertEqual(GooglePlayAccountConnection.reviewsPageSizeRange, 1...100)
    }

    // MARK: - Helpers

    private func assertOffline(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected OfflineError.noConnection", file: file, line: line)
        } catch OfflineError.noConnection {
            // Expected.
        } catch {
            XCTFail("Expected OfflineError.noConnection, got \(error)", file: file, line: line)
        }
    }

    private func assertInvalidCredentials(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected StackError.InvalidCredentials", file: file, line: line)
        } catch StackError.InvalidCredentials {
            // Expected.
        } catch {
            XCTFail("Expected StackError.InvalidCredentials, got \(error)", file: file, line: line)
        }
    }
}
