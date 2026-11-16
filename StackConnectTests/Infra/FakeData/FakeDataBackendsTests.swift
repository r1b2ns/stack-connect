import XCTest
import SwiftData
import APIProviderFirebase
import StackCoreRust
@testable import StackConnect

/// The fake backends serve the seeded data through the app's real connections
/// (only the core / Firebase seams are swapped), writes are reflected, and the
/// fake store never touches the App Group store or the Keychain.
@MainActor
final class FakeDataBackendsTests: XCTestCase {

    private let clock = FakeClock(now: Date(timeIntervalSince1970: 1_790_000_000))
    private var coreProviders: FakeCoreProviderFactory!

    override func setUp() async throws {
        try await super.setUp()
        coreProviders = FakeCoreProviderFactory(
            appStoreConnect: FakeAppStoreConnectBackend(clock: clock, teams: FakeAppStoreConnectCatalog.makeTeams(clock: clock)),
            googlePlay: FakeGooglePlayBackend(clock: clock, developers: FakeGooglePlayCatalog.makeDevelopers(clock: clock))
        )
    }

    override func tearDown() async throws {
        coreProviders = nil
        try await super.tearDown()
    }

    private func appleConnection(issuerId: String = FakeAppStoreConnectCatalog.northwindIssuerId) -> AppleAccountConnection {
        AppleAccountConnection(
            credentials: AppleCredentials(issuerID: issuerId, privateKeyID: "KEY", privateKey: "PEM"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: coreProviders
        )
    }

    private func playConnection() -> GooglePlayAccountConnection {
        let json = FakeDataSeeder.serviceAccountJSON(
            projectId: FakeGooglePlayCatalog.northwindProjectId,
            clientEmail: FakeGooglePlayCatalog.northwindClientEmail,
            privateKey: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----"
        )
        return GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(serviceAccountJSON: json),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: coreProviders
        )
    }

    // MARK: - App Store Connect

    func testAppStoreConnectServesSeededApps() async throws {
        let apps = try await appleConnection().fetchApps()
        XCTAssertEqual(Set(apps.map(\.name)), ["Trailhead", "Ledger Pocket", "Mosaic Notes", "Lumen", "Orbit Focus"])

        let personal = try await appleConnection(issuerId: FakeAppStoreConnectCatalog.personalIssuerId).fetchApps()
        XCTAssertEqual(Set(personal.map(\.name)), ["Tide Tables", "Pocket Haiku"])
    }

    func testAppStoreConnectVersionsCoverEveryState() async throws {
        let connection = appleConnection()
        var states: Set<AppStoreState> = []
        for app in try await connection.fetchApps() {
            for version in try await connection.fetchAppStoreVersions(appId: app.id) {
                if let state = version.appStoreState { states.insert(state) }
            }
        }
        XCTAssertTrue(states.isSuperset(of: [.readyForSale, .inReview, .waitingForReview, .pendingDeveloperRelease,
                                             .rejected, .prepareForSubmission]))
    }

    func testPhasedReleaseIsOnDayThree() async throws {
        let connection = appleConnection()
        let trailhead = try await connection.fetchAppStoreVersions(appId: FakeAppStoreConnectCatalog.trailhead.id)
        let live = try XCTUnwrap(trailhead.first { $0.versionString == "4.2.0" })
        let phased = try await connection.fetchPhasedRelease(versionId: live.id)
        XCTAssertEqual(phased?.state, .active)
        XCTAssertEqual(phased?.currentDayNumber, 3)
    }

    func testReplyIsReflectedOnTheNextRead() async throws {
        let appId = FakeAppStoreConnectCatalog.ledger.id
        let reviews = try await appleConnection().fetchRecentReviews(appId: appId, limit: 50)
        let unanswered = try XCTUnwrap(reviews.first { $0.responseBody == nil })

        _ = try await appleConnection().replyToReview(reviewId: unanswered.id, responseBody: "Thanks for the feedback!")

        // A new connection (another screen) sees the reply.
        let reread = try await appleConnection().fetchRecentReviews(appId: appId, limit: 50)
        XCTAssertEqual(reread.first { $0.id == unanswered.id }?.responseBody, "Thanks for the feedback!")
    }

    func testUnknownIssuerGetsAnEmptyTeam() async throws {
        let apps = try await appleConnection(issuerId: "new-issuer").fetchApps()
        XCTAssertTrue(apps.isEmpty)
    }

    func testFakeSyncServiceWritesAppBlobs() async throws {
        let store = RecordingBlobStore()
        let apps = try await appleConnection().syncApps(accountId: "account-1", store: store)

        XCTAssertEqual(apps.count, 5)
        let saved = store.saved
        XCTAssertEqual(saved.count, 5)
        XCTAssertTrue(saved.allSatisfy { $0.typeName == "app" })
        let blob = try JSONDecoder().decode(CoreAppBlob.self, from: Data(try XCTUnwrap(saved.first?.json).utf8))
        XCTAssertEqual(blob.accountId, "account-1")
    }

    // MARK: - Google Play

    func testGooglePlayServesTheNorthwindApps() async throws {
        let packages = try await playConnection().fetchApps().map(\.id)
        XCTAssertEqual(Set(packages), ["com.northwind.trailhead", "com.northwind.ledger", "com.northwind.mosaic", "com.northwind.harbor"])
    }

    func testGooglePlayTracksIncludeStagedAndHaltedRollouts() async throws {
        let trailhead = try await playConnection().fetchTracks(packageName: "com.northwind.trailhead")
        let production = try XCTUnwrap(trailhead.first { $0.track == "production" })
        XCTAssertEqual(production.releases.first?.status, .inProgress)
        XCTAssertEqual(production.releases.first?.rolloutFraction, 0.2)

        let ledger = try await playConnection().fetchTracks(packageName: "com.northwind.ledger")
        XCTAssertTrue(ledger.flatMap(\.releases).contains { $0.status == .halted })
    }

    func testGooglePlayIconIsALocalFakeImage() async throws {
        let fetched = await playConnection().fetchIconUrl(packageName: "com.northwind.mosaic")
        let icon = try XCTUnwrap(fetched)
        let url = try XCTUnwrap(URL(string: icon))
        XCTAssertEqual(url.host, FakeMedia.host)
        XCTAssertNotNil(FakeMedia.pngData(for: url))
    }

    func testGooglePlayReplyAndUnknownPackage() async throws {
        let connection = playConnection()
        let page = try await connection.fetchCustomerReviewsPage(packageName: "com.northwind.ledger", filterRating: nil, limit: 20, pageToken: nil)
        let review = try XCTUnwrap(page.reviews.first)
        _ = try await connection.replyToReview(reviewId: review.id, body: "Thank you!")
        let reread = try await connection.fetchCustomerReviewsPage(packageName: "com.northwind.ledger", filterRating: nil, limit: 20, pageToken: nil)
        XCTAssertEqual(reread.reviews.first { $0.id == review.id }?.responseBody, "Thank you!")

        do {
            _ = try await connection.fetchAppDetails(packageName: "com.example.unknown")
            XCTFail("Expected a 404")
        } catch let StackError.Http(status, _) {
            XCTAssertEqual(status, 404)
        }
    }

    // MARK: - Google Play release management and users (core handles)

    private func playProvider() -> FakeGooglePlayProvider {
        let developer = FakeGooglePlayBackend(clock: clock, developers: FakeGooglePlayCatalog.makeDevelopers(clock: clock))
            .developer(clientEmail: FakeGooglePlayCatalog.northwindClientEmail)
        return FakeGooglePlayProvider(developer: developer)
    }

    func testGooglePlayCapabilitiesMatchTheCore() throws {
        let provider = playProvider()
        XCTAssertEqual(provider.capabilities(), [.apps, .reviews, .appDetails, .storeListings, .tracks, .appIcons, .releaseManagement, .playUsers])
        XCTAssertNotNil(provider.playUsers())
    }

    func testGooglePlayReleaseSummariesSpreadEveryLifecycleState() async throws {
        let tracks = try XCTUnwrap(playProvider().tracks())
        var states: Set<String> = []
        for app in FakeGooglePlayCatalog.apps {
            for track in ["production", "beta", "alpha", "internal"] {
                for summary in try await tracks.fetchReleaseSummaries(appId: app.packageName, track: track) {
                    XCTAssertEqual(summary.track, track)
                    states.insert(try XCTUnwrap(summary.lifecycleState))
                }
            }
        }
        XCTAssertEqual(states, [
            "RELEASE_LIFECYCLE_STATE_DRAFT", "RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW", "RELEASE_LIFECYCLE_STATE_IN_REVIEW",
            "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED", "RELEASE_LIFECYCLE_STATE_NOT_APPROVED", "RELEASE_LIFECYCLE_STATE_PUBLISHED"
        ])
        let unknownTrack = try await tracks.fetchReleaseSummaries(appId: "com.northwind.trailhead", track: "no-such-track")
        XCTAssertTrue(unknownTrack.isEmpty, "An unknown track is an empty list, like the core's 404 mapping")
    }

    func testGooglePlayBundlesIncludeAnUnreleasedBuild() async throws {
        let bundles = try await XCTUnwrap(playProvider().tracks()).fetchBundles(appId: "com.northwind.trailhead")
        XCTAssertEqual(bundles.first?.versionCode, "4306")
        XCTAssertTrue(bundles.allSatisfy { $0.sha256?.count == 64 })
    }

    func testGooglePlayReleaseChangeIsReflectedOnTheNextRead() async throws {
        let tracks = try XCTUnwrap(playProvider().tracks())
        let committed = try await tracks.applyReleaseChange(
            appId: "com.northwind.trailhead", track: "production",
            change: .setRollout(versionCodes: ["4210"], userFraction: 0.5),
            options: CommitOptions(sendForReview: true, changesInReviewBehavior: nil)
        )
        XCTAssertEqual(committed.releases.first?.userFraction, 0.5)
        let reread = try await tracks.fetchTracks(appId: "com.northwind.trailhead")
        XCTAssertEqual(reread.first { $0.track == "production" }?.releases.first?.userFraction, 0.5)

        do {
            _ = try await tracks.applyReleaseChange(
                appId: "com.northwind.trailhead", track: "production",
                change: .halt(versionCodes: ["9999"]),
                options: CommitOptions(sendForReview: true, changesInReviewBehavior: nil)
            )
            XCTFail("Expected ReleaseNotFound")
        } catch StackError.ReleaseNotFound {
        }
        do {
            _ = try await tracks.applyReleaseChange(
                appId: "com.northwind.trailhead", track: "production",
                change: .setRollout(versionCodes: ["4210"], userFraction: 1),
                options: CommitOptions(sendForReview: true, changesInReviewBehavior: nil)
            )
            XCTFail("Expected an HTTP 400")
        } catch let StackError.Http(status, _) {
            XCTAssertEqual(status, 400)
        }
    }

    func testGooglePlayCreateReleaseOnInternalReplacesTheDraft() async throws {
        let tracks = try XCTUnwrap(playProvider().tracks())
        let committed = try await tracks.applyReleaseChange(
            appId: "com.northwind.trailhead", track: "internal",
            change: .createRelease(release: NewRelease(versionCodes: ["4306"], name: "4.3.0 (4306)", releaseNotes: [],
                                                       status: .draft, inAppUpdatePriority: nil, countryTargeting: nil)),
            options: CommitOptions(sendForReview: false, changesInReviewBehavior: nil)
        )
        XCTAssertEqual(committed.releases.map(\.versionCodes), [["4306"], ["4303"]])
    }

    func testGooglePlayUsersInviteAndDelete() async throws {
        let users = try XCTUnwrap(playProvider().playUsers())
        let before = try await users.fetchUsers(developerId: "1234567890")
        XCTAssertFalse(before.isEmpty)

        _ = try await users.inviteUser(developerId: "1234567890", email: "new@northwind.example",
                                       accountPermissions: [], grants: [], expirationTime: nil)
        _ = try await users.setGrant(developerId: "1234567890", email: "new@northwind.example",
                                     packageName: "com.northwind.mosaic", appLevelPermissions: ["CAN_REPLY_TO_REVIEWS"])
        let invited = try await users.fetchUsers(developerId: "1234567890").first { $0.email == "new@northwind.example" }
        XCTAssertEqual(invited?.accessState, "INVITED")
        XCTAssertEqual(invited?.grants.map(\.packageName), ["com.northwind.mosaic"])

        try await users.deleteUser(developerId: "1234567890", email: "new@northwind.example")
        let after = try await users.fetchUsers(developerId: "1234567890")
        XCTAssertEqual(after.count, before.count)

        do {
            _ = try await users.fetchUsers(developerId: "not-a-number")
            XCTFail("Expected a 404")
        } catch let StackError.Http(status, _) {
            XCTAssertEqual(status, 404)
        }
    }

    // MARK: - Firebase

    func testFirebaseServerListsProjectsThroughTheRealProvider() async throws {
        let keys = FakeKeyStorable()
        FakeDataSeeder.writeCredentials(into: keys)
        let credentials: FirebaseCredentials = try XCTUnwrap(keys.object(forKey: "credentials.\(FakeDataSeeder.AccountID.northwindFirebase)"))
        let factory = FakeFirebaseProviderFactory(server: FakeFirebaseServer(clock: clock))
        let provider = try XCTUnwrap(factory.makeProvider(serviceAccountJSON: credentials.serviceAccountJSON))

        let projects = try await provider.request(FirebaseAPI.v1beta1.projects.get(pageSize: 100))
        XCTAssertEqual(Set(projects.results?.compactMap(\.projectId) ?? []), ["trailhead-prod-4f2a1", "mosaic-notes-91c0e"])

        let apps = try await provider.request(FirebaseAPI.v1beta1.projects.id("trailhead-prod-4f2a1").androidApps.get())
        XCTAssertEqual(apps.apps?.count, 2)

        let (template, headers) = try await provider.requestWithHeaders(FirebaseAPI.v1.remoteConfig(projectId: "trailhead-prod-4f2a1").get())
        XCTAssertFalse(template.parameters?.isEmpty ?? true)
        XCTAssertNotNil(headers["ETag"])
    }

    // MARK: - Isolation

    func testSeededCredentialsLiveOnlyInTheFakeKeyStore() {
        let keys = FakeKeyStorable()
        FakeDataSeeder.writeCredentials(into: keys)
        XCTAssertEqual(Set(keys.keys), [
            "credentials.\(FakeDataSeeder.AccountID.northwindAppStore)",
            "credentials.\(FakeDataSeeder.AccountID.personalAppStore)",
            "credentials.\(FakeDataSeeder.AccountID.northwindGooglePlay)",
            "credentials.\(FakeDataSeeder.AccountID.northwindFirebase)"
        ])
        let apple: AppleCredentials? = keys.object(forKey: "credentials.\(FakeDataSeeder.AccountID.northwindAppStore)")
        XCTAssertEqual(apple?.issuerID, FakeAppStoreConnectCatalog.northwindIssuerId)
    }

    func testFakeStoreIsOutsideTheAppGroupAndSeedsAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FakeDataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = FakeDataBootstrap.storeURL(in: directory)
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) {
            XCTAssertFalse(storeURL.path.hasPrefix(group.path))
        }

        let container = try FakeDataBootstrap.makeContainer(directory: directory)
        try FakeDataSeeder.seedIfNeeded(container: container, clock: clock)
        // Seeding twice is a no-op.
        try FakeDataSeeder.seedIfNeeded(container: container, clock: clock)

        let items = try ModelContext(container).fetch(FetchDescriptor<PersistedItem>())
        let accounts = items.filter { $0.typeName == String(describing: AccountModel.self) }
        XCTAssertEqual(accounts.count, 4)
        XCTAssertEqual(Set(accounts.map(\.identifier)), Set(FakeDataSeeder.accounts(clock: clock).map(\.id)))
    }
}

/// Records what the fake sync service writes.
private final class RecordingBlobStore: BlobStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(typeName: String, id: String, json: String)] = []

    var saved: [(typeName: String, id: String, json: String)] {
        lock.withLock { entries }
    }

    func save(typeName: String, id: String, json: String) {
        lock.withLock { entries.append((typeName, id, json)) }
    }

    func fetch(typeName: String, id: String) -> String? { nil }
    func fetchAll(typeName: String) -> [String] { [] }
    func delete(typeName: String, id: String) {}
}
