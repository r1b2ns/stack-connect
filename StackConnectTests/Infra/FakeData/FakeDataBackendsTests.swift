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

    func testTideTablesPhasedReleaseIsOnDayTwo() async throws {
        let connection = appleConnection(issuerId: FakeAppStoreConnectCatalog.personalIssuerId)
        let tideTables = try await connection.fetchAppStoreVersions(appId: FakeAppStoreConnectCatalog.tideTables.id)
        let live = try XCTUnwrap(tideTables.first { $0.versionString == "1.6.0" })
        let phased = try await connection.fetchPhasedRelease(versionId: live.id)
        XCTAssertEqual(phased?.state, .active)
        XCTAssertEqual(phased?.currentDayNumber, 2)
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
                let summaries: [ReleaseSummaryInfo]
                do {
                    summaries = try await tracks.fetchReleaseSummaries(appId: app.packageName, track: track)
                } catch where GooglePlayEmptyReleaseList.isEmptyBody(error) {
                    continue // A track without releases (Google's 204).
                }
                for summary in summaries {
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

    /// Google answers `releases.list` of a track without releases with 204 No
    /// Content, which the vendored core fails to decode; the connection reads
    /// that as an empty list, so the app is still cached.
    func testAnEmptyTrackIsGooglesNoContentAndTheConnectionReadsItAsEmpty() async throws {
        let tracks = try XCTUnwrap(playProvider().tracks())
        do {
            _ = try await tracks.fetchReleaseSummaries(appId: "com.northwind.trailhead", track: "alpha")
            XCTFail("Expected the core's empty-body decode error")
        } catch {
            XCTAssertTrue(GooglePlayEmptyReleaseList.isEmptyBody(error))
        }

        let connection = playConnection()
        let empty = try await connection.fetchReleaseSummaries(packageName: "com.northwind.trailhead", track: "alpha")
        XCTAssertTrue(empty.isEmpty)
        let production = try await connection.fetchReleaseSummaries(packageName: "com.northwind.trailhead", track: "production")
        XCTAssertFalse(production.isEmpty)
    }

    func testOnlyTheCoresEmptyBodyDecodeErrorIsAnEmptyReleaseList() {
        XCTAssertTrue(GooglePlayEmptyReleaseList.isEmptyBody(
            StackError.Decode(message: "tracks.releases.list response: EOF while parsing a value at line 1 column 0")
        ))
        XCTAssertFalse(GooglePlayEmptyReleaseList.isEmptyBody(
            StackError.Decode(message: "tracks.releases.list response: expected value at line 1 column 1")
        ), "A malformed body is still an error")
        XCTAssertFalse(GooglePlayEmptyReleaseList.isEmptyBody(
            StackError.Decode(message: "edits.tracks response: EOF while parsing a value at line 1 column 0")
        ), "Only releases.list")
        XCTAssertFalse(GooglePlayEmptyReleaseList.isEmptyBody(StackError.Http(status: 204, message: "")))
        XCTAssertFalse(GooglePlayEmptyReleaseList.isEmptyBody(URLError(.zeroByteResource)))
    }

    /// `-StackFakePlayQuota YES`: every release summary answers with the
    /// core's quota error, which the app reads as a quota hit.
    func testGooglePlayReleaseSummariesCanSimulateTheQuota() async throws {
        let developer = FakeGooglePlayBackend(clock: clock, developers: FakeGooglePlayCatalog.makeDevelopers(clock: clock))
            .developer(clientEmail: FakeGooglePlayCatalog.northwindClientEmail)
        developer.state.write { $0.releaseSummariesQuotaExceeded = true }
        let tracks = try XCTUnwrap(FakeGooglePlayProvider(developer: developer).tracks())

        do {
            _ = try await tracks.fetchReleaseSummaries(appId: "com.northwind.trailhead", track: "production")
            XCTFail("Expected the quota error")
        } catch {
            let hit = try XCTUnwrap(GooglePlayQuota.hit(from: error))
            XCTAssertEqual(hit.retryAfter, 60)
            XCTAssertTrue(hit.message.hasSuffix("(HTTP 403 on GET applications/com.northwind.trailhead/tracks/production/releases)"))
        }
        let fetched = try await tracks.fetchTracks(appId: "com.northwind.trailhead")
        XCTAssertFalse(fetched.isEmpty, "Only release summaries hit the quota")
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
        do {
            _ = try await tracks.applyReleaseChange(
                appId: "com.northwind.trailhead", track: "production",
                change: .updateMetadata(versionCodes: ["4210"], update: ReleaseMetadataUpdate(
                    name: nil, releaseNotes: [LocalizedTextInfo(language: "en-US", text: String(repeating: "a", count: 501))],
                    inAppUpdatePriority: nil, countryTargeting: nil
                )),
                options: CommitOptions(sendForReview: true, changesInReviewBehavior: nil)
            )
            XCTFail("Expected Google's release notes validation")
        } catch let StackError.Http(status, message) {
            XCTAssertEqual(status, 400)
            XCTAssertTrue(message.contains("en-US"))
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
        } catch let StackError.Http(status, message) {
            XCTAssertEqual(status, 404)
            XCTAssertTrue(GooglePlayErrorTranslator.isLocalRejection(message), "Mirrors the core's local check: \(message)")
            XCTAssertEqual(
                message,
                "local validation failed: developer ID \"not-a-number\" is not numeric (12 chars: letters, '-'); "
                    + "it is the number after /developers/ in a Play Console URL; request not sent to Google",
                "Worded exactly like the core's ensure_developer_id"
            )
        }
    }

    /// `FakeCoreError.playQuotaExceeded` reads exactly like the core's quota
    /// mapping (`quota_exceeded` + `with_request_context`): Http 429 whatever
    /// Google answered, with and without a `Retry-After`.
    func testFakePlayQuotaErrorMirrorsTheCoresWording() {
        guard case let .Http(status, message) = FakeCoreError.playQuotaExceeded(
            retryAfterSeconds: 60, request: "GET applications/com.example.app/tracks/production/releases"
        ) else { return XCTFail("Expected Http") }
        XCTAssertEqual(status, 429)
        XCTAssertEqual(
            message,
            "Listing releases quota exceeded. [PERMISSION_DENIED]; this is a Google Play API quota/rate limit, "
                + "not a permission problem — wait and retry later (Retry-After: 60 s) "
                + "(HTTP 403 on GET applications/com.example.app/tracks/production/releases)"
        )

        guard case let .Http(_, plain) = FakeCoreError.playQuotaExceeded(
            googleMessage: "Quota exceeded", googleStatus: "RESOURCE_EXHAUSTED", answeredStatus: 429, request: "GET v1beta1/apps:search"
        ) else { return XCTFail("Expected Http") }
        XCTAssertEqual(
            plain,
            "Quota exceeded [RESOURCE_EXHAUSTED]; this is a Google Play API quota/rate limit, not a permission problem "
                + "— wait and retry later (HTTP 429 on GET v1beta1/apps:search)"
        )
    }

    /// `FakeCoreMessage` mirrors the core's `quoted` / `shape`
    /// (`logging/redact.rs`), including its own unit-test expectations.
    func testFakeCoreMessageMirrorsTheCoresEchoHelpers() {
        XCTAssertEqual(FakeCoreMessage.shape(""), "0 chars")
        XCTAssertEqual(FakeCoreMessage.shape("7"), "1 char: digits")
        XCTAssertEqual(FakeCoreMessage.shape("abc"), "3 chars: letters")
        XCTAssertEqual(FakeCoreMessage.shape(" 5374 "), "6 chars: digits, whitespace")
        XCTAssertEqual(FakeCoreMessage.shape("a/b-c/d"), "7 chars: letters, '/', '-'")
        XCTAssertEqual(FakeCoreMessage.shape("!@#$%^&"), "7 chars: '!', '@', '#', '$', '%', …")
        XCTAssertEqual(FakeCoreMessage.quoted("abc"), "\"abc\"")
        XCTAssertEqual(FakeCoreMessage.quoted(""), "\"\"")
        XCTAssertEqual(FakeCoreMessage.quoted(String(repeating: "x", count: 70)), "\"\(String(repeating: "x", count: 64))\"…")
        XCTAssertEqual(FakeCoreMessage.quoted(String(repeating: "x", count: 64)), "\"\(String(repeating: "x", count: 64))\"")
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

    private func firebaseProvider() throws -> APIProviderFirebase {
        let keys = FakeKeyStorable()
        FakeDataSeeder.writeCredentials(into: keys)
        let credentials: FirebaseCredentials = try XCTUnwrap(keys.object(forKey: "credentials.\(FakeDataSeeder.AccountID.northwindFirebase)"))
        let factory = FakeFirebaseProviderFactory(server: FakeFirebaseServer(clock: clock))
        return try XCTUnwrap(factory.makeProvider(serviceAccountJSON: credentials.serviceAccountJSON))
    }

    /// App ids contain colons ("1:483920175624:ios:…"): the config route must
    /// resolve the full id the list returned, for every seeded app.
    func testFirebaseConfigFileServedForEverySeededApp() async throws {
        let provider = try firebaseProvider()
        for project in FakeFirebaseCatalog.projects {
            let projectPath = FirebaseAPI.v1beta1.projects.id(project.projectId)
            let ios = try await provider.request(projectPath.iosApps.get(pageSize: 100)).apps ?? []
            let android = try await provider.request(projectPath.androidApps.get(pageSize: 100)).apps ?? []
            let web = try await provider.request(projectPath.webApps.get(pageSize: 100)).apps ?? []
            XCTAssertEqual(ios.count + android.count + web.count, project.apps.count)

            for app in ios {
                let appId = try XCTUnwrap(app.appId)
                let config = try await provider.request(projectPath.iosApps.id(appId).config())
                XCTAssertEqual(config.configFilename, "GoogleService-Info.plist")
                let plist = try XCTUnwrap(config.configFileContents.flatMap { Data(base64Encoded: $0) })
                let dict = try XCTUnwrap(PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
                XCTAssertEqual(dict["GOOGLE_APP_ID"] as? String, appId)
                XCTAssertEqual(dict["BUNDLE_ID"] as? String, app.bundleId)
                XCTAssertEqual(dict["PROJECT_ID"] as? String, project.projectId)
                XCTAssertEqual(dict["GCM_SENDER_ID"] as? String, project.projectNumber)
            }
            for app in android {
                let appId = try XCTUnwrap(app.appId)
                let config = try await provider.request(projectPath.androidApps.id(appId).config())
                XCTAssertEqual(config.configFilename, "google-services.json")
                let data = try XCTUnwrap(config.configFileContents.flatMap { Data(base64Encoded: $0) })
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let info = try XCTUnwrap(json["project_info"] as? [String: Any])
                XCTAssertEqual(info["project_id"] as? String, project.projectId)
                let client = try XCTUnwrap((json["client"] as? [[String: Any]])?.first)
                let clientInfo = try XCTUnwrap(client["client_info"] as? [String: Any])
                XCTAssertEqual(clientInfo["mobilesdk_app_id"] as? String, appId)
                XCTAssertEqual((clientInfo["android_client_info"] as? [String: Any])?["package_name"] as? String, app.packageName)
            }
            for app in web {
                let appId = try XCTUnwrap(app.appId)
                let config = try await provider.request(projectPath.webApps.id(appId).config())
                XCTAssertNil(config.configFileContents)
                XCTAssertEqual(config.appId, appId)
                XCTAssertEqual(config.projectId, project.projectId)
                XCTAssertEqual(config.messagingSenderId, project.projectNumber)
                XCTAssertNotNil(config.apiKey)
                XCTAssertNotNil(config.authDomain)
            }
        }
    }

    func testFirebaseUnknownAppConfigIsNotFound() async throws {
        let provider = try firebaseProvider()
        do {
            _ = try await provider.request(FirebaseAPI.v1beta1.projects.id("trailhead-prod-4f2a1").iosApps.id("1:483920175624:ios:missing").config())
            XCTFail("Expected a 404")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("404"), error.localizedDescription)
        }
    }

    func testFirebaseRenameAndRemoveResolveColonAppIds() async throws {
        let provider = try firebaseProvider()
        let apps = FirebaseAPI.v1beta1.projects.id("trailhead-prod-4f2a1").androidApps
        let appId = "1:483920175624:android:3e9d7c1b5a2f4e60"

        let patched = try await provider.request(apps.id(appId).patch(PatchDisplayNameRequest(displayName: "Renamed"), updateMask: "displayName"))
        XCTAssertEqual(patched.displayName, "Renamed")

        _ = try await provider.request(apps.id(appId).remove())
        let remaining = try await provider.request(apps.get(pageSize: 100)).apps ?? []
        XCTAssertFalse(remaining.contains { $0.appId == appId })
        XCTAssertEqual(remaining.count, 1)
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
        try FakeDataSeeder.seedIfNeeded(container: container, clock: clock, includesGooglePlay: true)
        // Seeding twice is a no-op.
        try FakeDataSeeder.seedIfNeeded(container: container, clock: clock, includesGooglePlay: true)

        let items = try ModelContext(container).fetch(FetchDescriptor<PersistedItem>())
        let accounts = items.filter { $0.typeName == String(describing: AccountModel.self) }
        XCTAssertEqual(accounts.count, 4)
        XCTAssertEqual(Set(accounts.map(\.identifier)), Set(FakeDataSeeder.accounts(clock: clock).map(\.id)))
    }

    /// `googlePlayAccounts` OFF (screenshot sessions): no Google Play account
    /// nor tracks cache; flipping the flag re-seeds the store.
    func testFakeStoreSeedsNoGooglePlayWhenTheFlagIsOff() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FakeDataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try FakeDataBootstrap.makeContainer(directory: directory)

        try FakeDataSeeder.seedIfNeeded(container: container, clock: clock, includesGooglePlay: false)
        var items = try ModelContext(container).fetch(FetchDescriptor<PersistedItem>())
        var accountIds = Set(items.filter { $0.typeName == String(describing: AccountModel.self) }.map(\.identifier))
        XCTAssertEqual(accountIds.count, 3)
        XCTAssertFalse(accountIds.contains(FakeDataSeeder.AccountID.northwindGooglePlay))
        XCTAssertFalse(items.contains { $0.typeName == String(describing: GooglePlayTracksCache.self) })

        try FakeDataSeeder.seedIfNeeded(container: container, clock: clock, includesGooglePlay: true)
        items = try ModelContext(container).fetch(FetchDescriptor<PersistedItem>())
        accountIds = Set(items.filter { $0.typeName == String(describing: AccountModel.self) }.map(\.identifier))
        XCTAssertTrue(accountIds.contains(FakeDataSeeder.AccountID.northwindGooglePlay))
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
