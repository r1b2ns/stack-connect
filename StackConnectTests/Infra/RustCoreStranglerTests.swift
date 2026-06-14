import XCTest
import StackCore        // PersistentStorable
import StackCoreRust
@testable import StackConnect

/// Covers the first strangler step that routes the Apple connection's
/// `validateCredentials()` / `fetchApps()` through the shared Rust core behind the
/// `useRustCoreForAppleApps` feature flag.
final class RustCoreStranglerTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a `FeatureFlags` backed by an isolated, empty `UserDefaults` suite so
    /// tests never touch the shared store and can assert the OFF/ON states cleanly.
    private func makeFlags(rustCoreOn: Bool) -> FeatureFlags {
        let suiteName = "RustCoreStranglerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let flags = FeatureFlags(defaults: defaults)
        flags.setEnabled(rustCoreOn, for: .useRustCoreForAppleApps)
        return flags
    }

    private let invalidCredentials = AppleCredentials(
        issuerID: "00000000-0000-0000-0000-000000000000",
        privateKeyID: "ABCD1234EF",
        privateKey: "not-a-real-key"
    )

    /// Throwaway EC P-256 PKCS#8 private key (bare base64, no PEM armor — the form
    /// the app stores). It is *well-formed* so the Swift SDK's `APIConfiguration`
    /// parses it successfully, letting `createProvider()` build an `APIProvider`
    /// locally with no network. NOT a real Apple key.
    private let wellFormedCredentials = AppleCredentials(
        issuerID: "00000000-0000-0000-0000-000000000000",
        privateKeyID: "ABCD1234EF",
        privateKey: "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgNq00FIJGPS2dceTavvHniKrgQspy39Pn2k6vij01BZihRANCAAQw1YrXLyOyKjU4AUwTI5dWduXQSG78mWjW0PRzM3m29SKWZ2/n5YaFoKx3akDno+SdY6/AYY88UWOPgS9bobWM"
    )

    // MARK: - FeatureFlags

    func testFlagDefaultsOffWhenUnset() {
        let suiteName = "RustCoreStranglerTests.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let flags = FeatureFlags(defaults: defaults)

        XCTAssertFalse(
            flags.isEnabled(.useRustCoreForAppleApps),
            "New flag must default to OFF (safe, reversible)."
        )
    }

    func testFlagCanBeToggled() {
        let flags = makeFlags(rustCoreOn: true)
        XCTAssertTrue(flags.isEnabled(.useRustCoreForAppleApps))

        flags.setEnabled(false, for: .useRustCoreForAppleApps)
        XCTAssertFalse(flags.isEnabled(.useRustCoreForAppleApps))
    }

    // MARK: - AppleCredentialStore bridge

    func testCredentialStoreMapsRustKeysToAppleCredentials() {
        let store = AppleCredentialStore(credentials: invalidCredentials)

        XCTAssertEqual(
            store.secret(accountId: "acct", key: AppleCredentialStore.Key.issuerId),
            invalidCredentials.issuerID
        )
        XCTAssertEqual(
            store.secret(accountId: "acct", key: AppleCredentialStore.Key.keyId),
            invalidCredentials.privateKeyID
        )
        XCTAssertEqual(
            store.secret(accountId: "acct", key: AppleCredentialStore.Key.privateKeyP8),
            invalidCredentials.privateKey
        )
        XCTAssertNil(
            store.secret(accountId: "acct", key: "unknownKey"),
            "Unknown keys must return nil so the core takes its missing-credentials path."
        )
    }

    func testCredentialStoreKeysMatchRustSchema() {
        // Guards against drift between the app's hard-coded keys and the core's schema.
        let schemaKeys = credentialSchema(kind: .appStoreConnect).map(\.key)
        XCTAssertEqual(
            schemaKeys,
            [
                AppleCredentialStore.Key.issuerId,
                AppleCredentialStore.Key.keyId,
                AppleCredentialStore.Key.privateKeyP8
            ]
        )
    }

    // MARK: - Routing (ON path)

    /// With the flag ON, invalid credentials must surface a Rust-core `StackError`.
    /// This proves `validateCredentials()` is going through the Rust `Provider`
    /// (which validates the EC key locally) rather than the Swift SDK path.
    func testValidateRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            try await connection.validateCredentials()
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch let error as StackError {
            // Any StackError confirms the call crossed into the Rust core. The
            // malformed private key surfaces as .invalidCredentials.
            switch error {
            case .InvalidCredentials, .Auth, .PendingAgreements, .Network, .Http, .Decode, .Unsupported:
                break
            }
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `fetchApps()` must also fail via the Rust core for invalid
    /// credentials (it cannot reach the Swift-SDK provider, which is never built).
    func testFetchAppsRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            _ = try await connection.fetchApps()
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `syncApps(accountId:store:)` must also fail via the Rust
    /// core for invalid credentials, proving it crossed into the core's `SyncService`
    /// (it can never reach the Swift-SDK provider, which is never built).
    func testSyncAppsRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )
        let store = SwiftDataBlobStore(storage: InMemoryStorable())

        do {
            _ = try await connection.syncApps(accountId: "acct", store: store)
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `fetchReviewSubmissions(appId:)` must also fail via the Rust
    /// core for invalid credentials, proving it never reaches the Swift-SDK provider.
    func testFetchReviewSubmissionsRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            _ = try await connection.fetchReviewSubmissions(appId: "123456789")
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `replyToReview(reviewId:responseBody:)` must fail via the Rust
    /// core for invalid credentials, proving the write never reaches the Swift-SDK provider.
    func testReplyToReviewRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            try await connection.replyToReview(reviewId: "123", responseBody: "thanks")
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `deleteReviewResponse(responseId:)` must fail via the Rust
    /// core for invalid credentials, proving the write never reaches the Swift-SDK provider.
    func testDeleteReviewResponseRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            try await connection.deleteReviewResponse(responseId: "resp-1")
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `fetchAppStoreVersions(appId:limit:)` must fail via the Rust
    /// core for invalid credentials, proving the read never reaches the Swift-SDK provider.
    func testFetchAppStoreVersionsRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            _ = try await connection.fetchAppStoreVersions(appId: "123", limit: 20)
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `createAppStoreVersion(request:)` must fail via the Rust core
    /// for invalid credentials, proving the write never reaches the Swift-SDK provider.
    func testCreateAppStoreVersionRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )
        let request = CreateAppVersionRequest(appId: "123", platform: .ios, version: "1.0")

        do {
            _ = try await connection.createAppStoreVersion(request: request)
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `deleteAppStoreVersion(id:)` must fail via the Rust core
    /// for invalid credentials, proving the write never reaches the Swift-SDK provider.
    func testDeleteAppStoreVersionRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            try await connection.deleteAppStoreVersion(id: "v1")
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    /// With the flag ON, `updateAppStoreVersion(id:versionString:)` must fail via the
    /// Rust core for invalid credentials, proving the write never reaches the Swift-SDK provider.
    func testUpdateAppStoreVersionRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            try await connection.updateAppStoreVersion(id: "v1", versionString: "1.1")
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    // MARK: - App Store version mapping (Rust core -> app model)

    /// The core `AppStoreVersionInfo` must map field-for-field onto the app's
    /// `AppStoreVersionModel`, including ISO8601 date parsing of `createdDate` and
    /// raw-string -> enum mapping for `platform`/`appStoreState`.
    func testMapVersionInfoMapsAllFieldsParsesDateAndEnums() {
        let core = StackCoreRust.AppStoreVersionInfo(
            id: "ver-1",
            appId: "123456789",
            platform: "IOS",
            appStoreState: "READY_FOR_SALE",
            appVersionState: "ACCEPTED",
            versionString: "2.1.0",
            copyright: "2024 Acme",
            releaseType: "MANUAL",
            createdDate: "2024-01-15T10:30:00Z"
        )

        let model = AppleAccountConnection.mapVersionInfo(core)

        XCTAssertEqual(model.id, "ver-1")
        XCTAssertEqual(model.appId, "123456789")
        XCTAssertEqual(model.platform, .ios)
        XCTAssertEqual(model.appStoreState, AppStoreState(rawValue: "READY_FOR_SALE"))
        XCTAssertEqual(model.appVersionState, "ACCEPTED")
        XCTAssertEqual(model.versionString, "2.1.0")
        XCTAssertEqual(model.copyright, "2024 Acme")
        XCTAssertEqual(model.releaseType, "MANUAL")

        let expected = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")
        XCTAssertEqual(model.createdDate, expected)
    }

    /// Nil/unknown raw strings must yield nil enums and a nil `createdDate` without crashing.
    func testMapVersionInfoHandlesNilAndUnknownRawValues() {
        let core = StackCoreRust.AppStoreVersionInfo(
            id: "ver-2",
            appId: "1",
            platform: "NOT_A_PLATFORM",
            appStoreState: nil,
            appVersionState: nil,
            versionString: nil,
            copyright: nil,
            releaseType: nil,
            createdDate: nil
        )

        let model = AppleAccountConnection.mapVersionInfo(core)

        XCTAssertEqual(model.id, "ver-2")
        XCTAssertEqual(model.appId, "1")
        XCTAssertNil(model.platform, "Unknown platform raw value must map to nil, not crash.")
        XCTAssertNil(model.appStoreState)
        XCTAssertNil(model.createdDate)
    }

    // MARK: - Re-validation storm regression (issue #84)

    /// Regression guard for issue #84: with the flag ON, the Rust-core
    /// `validateCredentials()` path must SEED the Swift SDK `self.provider`.
    ///
    /// Why this matters: ~87 not-yet-migrated Swift-only methods begin with
    /// `guard let provider else { try await validateCredentials(); return try await <same>() }`.
    /// Before the fix the Rust path returned without setting `self.provider`, so
    /// every such method re-entered `validateCredentials()` (a network call) and
    /// retried into the same nil guard — a runaway storm of ~752 validate calls per
    /// sync that got the account rate-limited (HTTP 429).
    ///
    /// `establishSwiftProvider()` is exactly the seeding step the Rust validate path
    /// runs after a successful `provider.validate()`. We invoke it in isolation from
    /// the network `validate()` (which can't succeed against fake credentials in a
    /// unit test) and prove it flips `provider` nil -> non-nil with no network. With
    /// `provider` non-nil, the `guard let provider else { ... }` in every Swift-only
    /// method short-circuits, so none of them can re-enter `validateCredentials()`.
    func testRustCorePathSeedsSwiftProviderToPreventReValidationStorm() throws {
        let connection = AppleAccountConnection(
            credentials: wellFormedCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        XCTAssertFalse(
            connection.hasSwiftProviderForTesting,
            "Precondition: no Swift provider before validation — this nil is what made the Swift-only methods recurse."
        )

        // The seeding step the Rust validate path performs after `provider.validate()`.
        // Network-free: builds APIConfiguration/APIProvider from the stored key.
        try connection.establishSwiftProvider()

        XCTAssertTrue(
            connection.hasSwiftProviderForTesting,
            "After the Rust validate path seeds it, self.provider must be non-nil so the ~87 Swift-only methods' `guard let provider else { validateCredentials() }` short-circuits instead of re-validating (issue #84)."
        )
    }

    /// Seeding is safe to repeat: a second call (e.g. another sync on the same reused
    /// connection) keeps `provider` non-nil and does not throw or hit the network.
    func testEstablishSwiftProviderIsRepeatableAndNetworkFree() throws {
        let connection = AppleAccountConnection(
            credentials: wellFormedCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        try connection.establishSwiftProvider()
        try connection.establishSwiftProvider()

        XCTAssertTrue(connection.hasSwiftProviderForTesting)
    }

    // MARK: - Review submission mapping (Rust core -> app model)

    /// The core `ReviewSubmission` must map field-for-field onto the app's
    /// `ReviewSubmissionModel`, including ISO8601 date parsing of `submittedDate`.
    func testMapReviewSubmissionMapsAllFieldsAndParsesDate() {
        let core = StackCoreRust.ReviewSubmission(
            id: "sub-1",
            appId: "123456789",
            platform: "IOS",
            submittedDate: "2024-01-15T10:30:00Z",
            state: "IN_REVIEW",
            versionString: "2.1.0",
            versionId: "ver-1",
            submittedByName: "Jane Doe",
            submittedByEmail: "jane@example.com"
        )

        let model = AppleAccountConnection.mapReviewSubmission(core)

        XCTAssertEqual(model.id, "sub-1")
        XCTAssertEqual(model.appId, "123456789")
        XCTAssertEqual(model.platform, "IOS")
        XCTAssertEqual(model.state, "IN_REVIEW")
        XCTAssertEqual(model.versionString, "2.1.0")
        XCTAssertEqual(model.versionId, "ver-1")
        XCTAssertEqual(model.submittedByName, "Jane Doe")
        XCTAssertEqual(model.submittedByEmail, "jane@example.com")

        let expected = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")
        XCTAssertEqual(model.submittedDate, expected)
    }

    /// App Store Connect timestamps may include fractional seconds; the parser must
    /// tolerate that form too.
    func testMapReviewSubmissionParsesFractionalSecondsDate() {
        let core = StackCoreRust.ReviewSubmission(
            id: "sub-2",
            appId: "123456789",
            platform: nil,
            submittedDate: "2024-01-15T10:30:00.123Z",
            state: nil,
            versionString: nil,
            versionId: nil,
            submittedByName: nil,
            submittedByEmail: nil
        )

        let model = AppleAccountConnection.mapReviewSubmission(core)

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(model.submittedDate, withFractional.date(from: "2024-01-15T10:30:00.123Z"))
    }

    /// A nil or unparseable `submittedDate` must yield a nil `Date?` without crashing.
    func testMapReviewSubmissionHandlesMissingAndInvalidDate() {
        let missing = StackCoreRust.ReviewSubmission(
            id: "sub-3", appId: "1", platform: nil, submittedDate: nil,
            state: nil, versionString: nil, versionId: nil,
            submittedByName: nil, submittedByEmail: nil
        )
        XCTAssertNil(AppleAccountConnection.mapReviewSubmission(missing).submittedDate)

        let invalid = StackCoreRust.ReviewSubmission(
            id: "sub-4", appId: "1", platform: nil, submittedDate: "not-a-date",
            state: nil, versionString: nil, versionId: nil,
            submittedByName: nil, submittedByEmail: nil
        )
        XCTAssertNil(AppleAccountConnection.mapReviewSubmission(invalid).submittedDate)
    }

    // MARK: - Customer reviews paging (ON path)

    /// With the flag ON, `fetchCustomerReviewsPage(...)` must fail via the Rust core
    /// for invalid credentials, proving the paged read never reaches the Swift-SDK
    /// provider. Because `fetchCustomerReviews(...)` and `fetchRecentReviews(...)`
    /// both delegate to this method, routing it covers all three.
    func testFetchCustomerReviewsPageRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            _ = try await connection.fetchCustomerReviewsPage(
                appId: "123",
                sort: "-createdDate",
                filterRating: nil,
                limit: 10,
                pageAfterResponse: nil
            )
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    // MARK: - Customer review mapping (Rust core -> app model)

    /// The core `CustomerReview` must map field-for-field onto the app's
    /// `CustomerReviewModel`, including ISO8601 date parsing of `createdDate`/response
    /// date, `Int32 -> Int` rating conversion, and flattening of the developer response.
    func testMapCustomerReviewMapsAllFieldsParsesDatesAndFlattensResponse() {
        let core = StackCoreRust.CustomerReview(
            id: "rev-1",
            rating: 5,
            title: "Great app",
            body: "Love it.",
            reviewerNickname: "Jane",
            createdDate: "2024-01-15T10:30:00Z",
            territory: "USA",
            response: StackCoreRust.ReviewResponse(
                id: "resp-1",
                body: "Thanks!",
                state: "PUBLISHED",
                lastModifiedDate: "2024-02-20T08:00:00.123Z"
            )
        )

        let model = AppleAccountConnection.mapCustomerReview(core)

        XCTAssertEqual(model.id, "rev-1")
        XCTAssertEqual(model.rating, 5)
        XCTAssertEqual(model.title, "Great app")
        XCTAssertEqual(model.body, "Love it.")
        XCTAssertEqual(model.reviewerNickname, "Jane")
        XCTAssertEqual(model.territory, "USA")
        XCTAssertEqual(model.responseId, "resp-1")
        XCTAssertEqual(model.responseBody, "Thanks!")
        XCTAssertEqual(model.responseState, "PUBLISHED")

        let expectedCreated = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")
        XCTAssertEqual(model.createdDate, expectedCreated)

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(model.responseDate, withFractional.date(from: "2024-02-20T08:00:00.123Z"))
    }

    /// A review with no developer response and nil dates must map cleanly: nil
    /// response fields and nil `Date?`s, with the rating still converted.
    func testMapCustomerReviewHandlesMissingResponseAndDates() {
        let core = StackCoreRust.CustomerReview(
            id: "rev-2",
            rating: 1,
            title: nil,
            body: nil,
            reviewerNickname: nil,
            createdDate: nil,
            territory: nil,
            response: nil
        )

        let model = AppleAccountConnection.mapCustomerReview(core)

        XCTAssertEqual(model.id, "rev-2")
        XCTAssertEqual(model.rating, 1)
        XCTAssertNil(model.createdDate)
        XCTAssertNil(model.responseId)
        XCTAssertNil(model.responseBody)
        XCTAssertNil(model.responseState)
        XCTAssertNil(model.responseDate)
        XCTAssertFalse(model.hasResponse)
    }

    // MARK: - Builds eager list (ON path)

    /// With the flag ON, `fetchBuilds(appId:limit:)` must fail via the Rust core for
    /// invalid credentials, proving the eager-list read never reaches the Swift-SDK
    /// provider. `fetchBuildsPage(...)` intentionally stays on the Swift SDK and is not
    /// covered here.
    func testFetchBuildsRoutesThroughRustCoreWhenFlagOn() async {
        let connection = AppleAccountConnection(
            credentials: invalidCredentials,
            featureFlags: makeFlags(rustCoreOn: true)
        )

        do {
            _ = try await connection.fetchBuilds(appId: "123", limit: 50)
            XCTFail("Expected the Rust core to reject the invalid credentials.")
        } catch is StackError {
            // Crossed into the Rust core as expected.
        } catch {
            XCTFail("Expected a StackError from the Rust core, got: \(error)")
        }
    }

    // MARK: - Build mapping (Rust core -> app model)

    /// The core `BuildInfo` must map onto the app's `BuildModel` for the fields the
    /// core fetches, including ISO8601 parsing of `uploadedDate`/`expirationDate` and
    /// `expired? -> isExpired` defaulting. Fields sourced from `included` relationships
    /// the core does not request must stay at their defaults (known Rust-path degradation).
    func testMapBuildInfoMapsCoreFieldsParsesDatesAndDefaultsTheRest() {
        let core = StackCoreRust.BuildInfo(
            id: "build-1",
            appId: "123456789",
            version: "1232",
            uploadedDate: "2024-01-15T10:30:00Z",
            expired: true,
            processingState: "VALID",
            minOsVersion: "17.0",
            expirationDate: "2024-04-15T10:30:00.123Z"
        )

        let model = AppleAccountConnection.mapBuildInfo(core)

        XCTAssertEqual(model.id, "build-1")
        XCTAssertEqual(model.version, "1232")
        XCTAssertEqual(model.processingState, "VALID")
        XCTAssertEqual(model.minOsVersion, "17.0")
        XCTAssertTrue(model.isExpired)

        let expectedUploaded = ISO8601DateFormatter().date(from: "2024-01-15T10:30:00Z")
        XCTAssertEqual(model.uploadedDate, expectedUploaded)

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(model.expirationDate, withFractional.date(from: "2024-04-15T10:30:00.123Z"))

        // Known Rust-path degradation: relationship-sourced fields stay at defaults.
        XCTAssertNil(model.marketingVersion)
        XCTAssertNil(model.iconUrl)
        XCTAssertNil(model.platform)
        XCTAssertNil(model.externalBuildState)
        XCTAssertNil(model.betaReviewState)
        XCTAssertNil(model.submittedDate)
        XCTAssertNil(model.computedMinMacOsVersion)
        XCTAssertNil(model.computedMinVisionOsVersion)
        XCTAssertNil(model.buildAudienceType)
        XCTAssertNil(model.usesNonExemptEncryption)
        XCTAssertNil(model.internalBuildState)
        XCTAssertNil(model.autoNotifyEnabled)
    }

    /// A nil `expired` must default `isExpired` to `false`, and nil/unparseable dates
    /// must yield nil `Date?`s without crashing.
    func testMapBuildInfoHandlesNilExpiredAndMissingDates() {
        let core = StackCoreRust.BuildInfo(
            id: "build-2",
            appId: "1",
            version: nil,
            uploadedDate: nil,
            expired: nil,
            processingState: nil,
            minOsVersion: nil,
            expirationDate: "not-a-date"
        )

        let model = AppleAccountConnection.mapBuildInfo(core)

        XCTAssertEqual(model.id, "build-2")
        XCTAssertFalse(model.isExpired, "Nil `expired` must default to false.")
        XCTAssertNil(model.uploadedDate)
        XCTAssertNil(model.expirationDate, "Unparseable date must map to nil, not crash.")
    }

    // MARK: - Pending agreements detection (Rust core typed error)

    /// The translator must recognize the core's typed `StackError.PendingAgreements`
    /// so `SyncService`'s catch flags pending agreements on the Rust path too.
    func testIsPendingAgreementRecognizesRustCorePendingAgreementsError() {
        let error = StackCoreRust.StackError.PendingAgreements(message: "x")
        XCTAssertTrue(AppleAPIErrorTranslator.isPendingAgreement(error))
    }

    /// A different core error must NOT be treated as pending agreements.
    func testIsPendingAgreementIgnoresOtherRustCoreErrors() {
        let error = StackCoreRust.StackError.Auth(message: "nope")
        XCTAssertFalse(AppleAPIErrorTranslator.isPendingAgreement(error))
    }
}

// MARK: - Minimal in-memory PersistentStorable for the BlobStore-backed test

/// Minimal `PersistentStorable` so `syncApps(accountId:store:)` can be given a
/// concrete `SwiftDataBlobStore` without a real SwiftData `ModelContainer`. The
/// invalid-credentials test never reaches a successful core save, so a no-op-ish
/// in-memory store is sufficient here.
private actor InMemoryStorable: PersistentStorable {
    private var store: [String: [String: Data]] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func typeName<T>(for type: T.Type) -> String { String(describing: type) }

    func save<T: Codable>(_ item: T, id: String) async throws {
        guard let payload = try? encoder.encode(item) else { throw PersistentStorableError.encodingFailed }
        store[typeName(for: T.self), default: [:]][id] = payload
    }

    func fetch<T: Codable>(_ type: T.Type, id: String) async throws -> T? {
        guard let payload = store[typeName(for: type)]?[id] else { return nil }
        return try? decoder.decode(T.self, from: payload)
    }

    func fetchAll<T: Codable>(_ type: T.Type) async throws -> [T] {
        guard let bucket = store[typeName(for: type)] else { return [] }
        return bucket.values.compactMap { try? decoder.decode(T.self, from: $0) }
    }

    func delete<T: Codable>(_ type: T.Type, id: String) async throws {
        store[typeName(for: type)]?[id] = nil
    }

    func deleteAll<T: Codable>(_ type: T.Type) async throws {
        store[typeName(for: type)] = nil
    }
}
