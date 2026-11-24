import XCTest
import StackCoreRust
import StackProtocols
@testable import StackConnect

final class NetworkAuditCoreSinkTests: XCTestCase {

    private let now = NetworkAuditFixtures.now
    private var store: MockNetworkAuditStore!
    private var settings: MockNetworkAuditSettings!
    private var vault: NetworkAuditSecretVault!
    private var recorder: NetworkAuditRecorder!

    override func setUp() {
        super.setUp()
        store = MockNetworkAuditStore()
        settings = MockNetworkAuditSettings()
        vault = NetworkAuditSecretVault(keychain: MockKeyStorable())
        recorder = NetworkAuditRecorder(store: store, settings: settings, vault: vault, now: { NetworkAuditFixtures.now })
    }

    // MARK: - Fixtures

    private func entry(
        operation: String = "reviews.fetch_customer_reviews",
        parentOperation: String? = nil,
        attempt: UInt32 = 1,
        provider: NetworkAuditProvider = .appleApi,
        accountId: String? = "69a6de70-issuer",
        credentialKind: NetworkAuditCredentialKind = .unauthenticated,
        tokenExpiresAtMs: Int64? = nil,
        method: String = "GET",
        url: String = "https://api.appstoreconnect.apple.com/v1/apps/1/customerReviews?limit=200",
        requestHeaders: [StackCoreRust.NetworkAuditHeader] = [.init(name: "Accept", value: "application/json")],
        requestBody: String? = nil,
        requestBodyState: NetworkAuditBodyState = .empty,
        responseStatus: UInt16? = 200,
        responseHeaders: [StackCoreRust.NetworkAuditHeader] = [.init(name: "Content-Type", value: "application/json")],
        responseBody: String? = #"{"data":[]}"#,
        responseBodyState: NetworkAuditBodyState = .captured,
        error: String? = nil
    ) -> NetworkAuditEntry {
        NetworkAuditEntry(
            id: UUID().uuidString,
            startedAtMs: Int64(now.timeIntervalSince1970 * 1000),
            durationMs: 412,
            attempt: attempt,
            operation: operation,
            parentOperation: parentOperation,
            provider: provider,
            accountId: accountId,
            credentialKind: credentialKind,
            tokenExpiresAtMs: tokenExpiresAtMs,
            method: method,
            url: url,
            httpVersion: responseStatus == nil ? nil : "HTTP/2.0",
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            requestBodyState: requestBodyState,
            requestSizeBytes: UInt64(requestBody?.utf8.count ?? 0),
            responseStatus: responseStatus,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            responseBodyState: responseBodyState,
            responseSizeBytes: UInt64(responseBody?.utf8.count ?? 0),
            error: error
        )
    }

    private func makeEvent(_ entry: NetworkAuditEntry) throws -> NetworkAuditEvent {
        let (exchange, annotations) = try XCTUnwrap(NetworkAuditCoreEntryMapper.map(entry))
        return recorder.makeEvent(from: exchange, annotations: annotations)
    }

    private func encoded(_ event: NetworkAuditEvent) throws -> String {
        String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
    }

    // MARK: - Mapping

    func testEntryMapsToAnHTTPEvent() throws {
        let event = try makeEvent(entry(parentOperation: "sync.sync_apps", attempt: 2, provider: .appleApi))

        XCTAssertEqual(event.source, .rustCore)
        XCTAssertEqual(event.kind, .http)
        XCTAssertEqual(event.category, .apple)
        XCTAssertEqual(event.method, "GET")
        XCTAssertEqual(event.host, "api.appstoreconnect.apple.com")
        XCTAssertEqual(event.path, "/v1/apps/1/customerReviews?limit=200")
        XCTAssertEqual(event.statusCode, 200)
        XCTAssertEqual(event.date, now)
        XCTAssertEqual(event.duration ?? 0, 0.412, accuracy: 0.0001)
        XCTAssertEqual(event.connection, "HTTP/2")
        XCTAssertEqual(event.operation, "reviews.fetch_customer_reviews")
        XCTAssertEqual(event.origin, "\(String(localized: "Ratings and Reviews")) · fetch customer reviews")
        XCTAssertEqual(event.parentOrigin, String(localized: "Sync · apps"))
        XCTAssertEqual(event.attempt, 2)
    }

    func testProviderCategories() {
        XCTAssertEqual(NetworkAuditCoreEntryMapper.category(of: .appleApi), .apple)
        XCTAssertEqual(NetworkAuditCoreEntryMapper.category(of: .appleWebSession), .apple)
        XCTAssertEqual(NetworkAuditCoreEntryMapper.category(of: .googlePlay), .google)
        XCTAssertEqual(NetworkAuditCoreEntryMapper.category(of: .googleOauth), .google)
        XCTAssertEqual(NetworkAuditCoreEntryMapper.category(of: .firebase), .google)
        XCTAssertNil(NetworkAuditCoreEntryMapper.category(of: .other))
    }

    func testOtherProviderFallsBackToTheHostCatalog() throws {
        let event = try makeEvent(entry(provider: .other, url: "https://play.google.com/store/apps/details?id=com.example"))

        XCTAssertEqual(event.category, .google)
    }

    func testOperationTitles() {
        XCTAssertEqual(NetworkAuditOperationCatalog.title("google.oauth.token"), String(localized: "Google · service account token"))
        XCTAssertEqual(NetworkAuditOperationCatalog.title("new_handle.do_thing"), "New Handle · do thing")
        XCTAssertEqual(NetworkAuditOperationCatalog.title("weird"), "weird")
        XCTAssertNotNil(NetworkAuditOperationCatalog.purpose("provider.validate"))
        XCTAssertNil(NetworkAuditOperationCatalog.purpose("reviews.fetch_customer_reviews"))
    }

    func testPurposeFallsBackToTheHostCatalog() throws {
        let known = try makeEvent(entry(operation: "provider.validate"))
        let other = try makeEvent(entry())

        XCTAssertEqual(known.purpose, NetworkAuditOperationCatalog.purpose("provider.validate"))
        XCTAssertEqual(other.purpose, NetworkAuditHostCatalog.entry(host: "api.appstoreconnect.apple.com").purpose)
    }

    func testTransportFailure() throws {
        let event = try makeEvent(entry(responseStatus: nil, responseHeaders: [], responseBody: nil, responseBodyState: .unavailable, error: "error sending request"))

        XCTAssertNil(event.statusCode)
        XCTAssertFalse(event.isSuccess)
        XCTAssertEqual(event.errorDescription, "error sending request")
        XCTAssertEqual(event.responseBody.content, .unavailable)
        XCTAssertNil(event.connection)
    }

    func testBodyStates() throws {
        XCTAssertEqual(try makeEvent(entry(responseBody: nil, responseBodyState: .binary)).responseBody.content, .binary)
        XCTAssertEqual(try makeEvent(entry(responseBody: nil, responseBodyState: .notCaptured)).responseBody.content, .notRecorded)
        XCTAssertEqual(try makeEvent(entry(responseBody: nil, responseBodyState: .empty)).responseBody.content, .empty)
        let truncated = try makeEvent(entry(responseBody: #"{"data":[{"id":"1"#, responseBodyState: .truncated))
        XCTAssertTrue(truncated.responseBody.isTruncated)
        XCTAssertNotNil(truncated.responseBody.text)
    }

    func testFullBodiesOffStillKeepsOnlySizes() throws {
        settings.recordsFullBodies = false

        let event = try makeEvent(entry())

        XCTAssertEqual(event.responseBody.content, .notRecorded)
    }

    func testEachSetCookieIsKeptMasked() throws {
        let event = try makeEvent(entry(
            provider: .appleWebSession,
            credentialKind: .appleSessionCookie,
            url: "https://appstoreconnect.apple.com/olympus/v1/session",
            responseHeaders: [
                .init(name: "Set-Cookie", value: "myacinfo=SESSION1; Path=/; Secure"),
                .init(name: "Set-Cookie", value: "dqsid=SESSION2; Path=/")
            ]
        ))

        XCTAssertEqual(event.responseHeaders.map(\.value), ["myacinfo=[MASKED]; Path=/; Secure", "dqsid=[MASKED]; Path=/"])
        XCTAssertFalse(try encoded(event).contains("SESSION"))
        let secrets = try XCTUnwrap(vault.open(try XCTUnwrap(event.sealedSecrets)))
        XCTAssertEqual(secrets.count, 2)
    }

    // MARK: - Apple ID sign-in (SRP / 2FA)

    func testSRPValuesAreMaskedForGood() throws {
        let start = try makeEvent(entry(
            operation: "apple_id.start",
            provider: .appleWebSession,
            accountId: nil,
            credentialKind: .unauthenticated,
            method: "POST",
            url: "https://idmsa.apple.com/appleauth/auth/signin/init",
            requestHeaders: [.init(name: "Content-Type", value: "application/json"), .init(name: "scnt", value: "SCNTSECRET")],
            requestBody: #"{"a":"AAAASRPA","accountName":"me@example.com","protocols":["s2k","s2k_fo"]}"#,
            requestBodyState: .captured,
            responseBody: #"{"iteration":20309,"salt":"SALTVALUE","protocol":"s2k","b":"BBBBSRPB","c":"CCCCSRPC"}"#
        ))
        let complete = try makeEvent(entry(
            operation: "apple_id.start",
            provider: .appleWebSession,
            accountId: nil,
            method: "POST",
            url: "https://idmsa.apple.com/appleauth/auth/signin/complete?isRememberMeEnabled=true",
            requestBody: #"{"accountName":"me@example.com","c":"CCCCSRPC","m1":"M1PROOF","m2":"M2PROOF","rememberMe":true}"#,
            requestBodyState: .captured,
            responseBody: nil,
            responseBodyState: .empty
        ))

        for event in [start, complete] {
            let json = try encoded(event)
            for secret in ["AAAASRPA", "SALTVALUE", "BBBBSRPB", "CCCCSRPC", "M1PROOF", "M2PROOF", "SCNTSECRET"] {
                XCTAssertFalse(json.contains(secret), secret)
            }
            // Never revealable either: only secret headers are sealed.
            let sealed = event.sealedSecrets.flatMap(vault.open)?.values.joined() ?? ""
            for secret in ["AAAASRPA", "SALTVALUE", "BBBBSRPB", "CCCCSRPC", "M1PROOF", "M2PROOF"] {
                XCTAssertFalse(sealed.contains(secret), secret)
            }
        }
        XCTAssertTrue(start.requestBody.text?.contains("me@example.com") ?? false)
        XCTAssertTrue(start.responseBody.text?.contains("20309") ?? false)
    }

    func testTwoFactorCodeIsMaskedForGood() throws {
        let event = try makeEvent(entry(
            operation: "apple_id.submit_code",
            provider: .appleWebSession,
            accountId: nil,
            method: "POST",
            url: "https://idmsa.apple.com/appleauth/auth/verify/trusteddevice/securitycode",
            requestBody: #"{"securityCode":{"code":"482913"}}"#,
            requestBodyState: .captured,
            responseStatus: 204,
            responseBody: nil,
            responseBodyState: .empty
        ))
        let sms = try makeEvent(entry(
            operation: "apple_id.submit_code",
            provider: .appleWebSession,
            accountId: nil,
            method: "POST",
            url: "https://idmsa.apple.com/appleauth/auth/verify/phone/securitycode",
            requestBody: #"{"phoneNumber":{"id":1},"securityCode":{"code":"771205"},"mode":"sms"}"#,
            requestBodyState: .captured
        ))

        XCTAssertFalse(try encoded(event).contains("482913"))
        XCTAssertFalse(try encoded(sms).contains("771205"))
        XCTAssertTrue(sms.requestBody.text?.contains("\"mode\" : \"sms\"") ?? false)
    }

    func testSRPFieldNamesAreOnlyMaskedForTheSignIn() throws {
        // A one-letter field elsewhere is data, not an SRP value.
        let event = try makeEvent(entry(responseBody: #"{"a":"keep-me"}"#))

        XCTAssertTrue(event.responseBody.text?.contains("keep-me") ?? false)
    }

    // MARK: - Google token exchange

    func testTokenResponseIsMaskedAndGivesTheAccessTokenAnExpiry() throws {
        let assertion = NetworkAuditFixtures.jwt(["iss": "bot@project.iam.gserviceaccount.com", "aud": "https://oauth2.googleapis.com/token", "exp": 1_900_000_000])
        let exchange = try makeEvent(entry(
            operation: "google.oauth.token",
            parentOperation: "tracks.fetch_tracks",
            provider: .googleOauth,
            accountId: "bot@project.iam.gserviceaccount.com",
            credentialKind: .oauthAssertion,
            tokenExpiresAtMs: 1_900_000_000_000,
            method: "POST",
            url: "https://oauth2.googleapis.com/token",
            requestHeaders: [.init(name: "Content-Type", value: "application/x-www-form-urlencoded")],
            requestBody: "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(assertion)",
            requestBodyState: .captured,
            responseBody: #"{"access_token":"ya29.c.LIVE_ACCESS_TOKEN_123","expires_in":3599,"token_type":"Bearer"}"#
        ))

        let json = try encoded(exchange)
        XCTAssertFalse(json.contains(assertion))
        XCTAssertFalse(json.contains("LIVE_ACCESS_TOKEN"))
        XCTAssertEqual(exchange.credential?.kind, .oauthAssertion)
        XCTAssertNil(exchange.credential?.expiresAt)
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(exchange, now: now), .notApplicable)
        XCTAssertEqual(exchange.parentOrigin, "\(String(localized: "Google Play Releases")) · fetch tracks")

        // The opaque access token the response issued: expiry from the response.
        let call = try makeEvent(entry(
            operation: "tracks.fetch_tracks",
            provider: .googlePlay,
            credentialKind: .googleAccessToken,
            url: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.example/edits/1/tracks",
            requestHeaders: [.init(name: "Authorization", value: "Bearer ya29.c.LIVE_ACCESS_TOKEN_123")]
        ))
        XCTAssertEqual(call.credential?.kind, .googleAccessToken)
        XCTAssertEqual(call.credential?.expiresAt?.timeIntervalSince1970 ?? 0,
                       now.addingTimeInterval(0.412 + 3599).timeIntervalSince1970, accuracy: 0.01)
        XCTAssertTrue(NetworkAuditTokenInclusion.evaluate(call, now: now).canInclude)
    }

    // MARK: - Credential rules

    func testAppStoreConnectJWTUsesTheCoreExpiry() throws {
        let decodedExpiry = now.addingTimeInterval(1_200)
        let coreExpiry = now.addingTimeInterval(300)
        let event = try makeEvent(entry(
            credentialKind: .ascJwt,
            tokenExpiresAtMs: Int64(coreExpiry.timeIntervalSince1970 * 1000),
            requestHeaders: [.init(name: "Authorization", value: "Bearer \(NetworkAuditFixtures.ascJWT(expiresAt: decodedExpiry))")]
        ))

        XCTAssertEqual(event.credential, NetworkAuditCredentialInfo(kind: .appStoreConnectJWT, expiresAt: coreExpiry))
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(event, now: now), .available(.appStoreConnectJWT, until: coreExpiry))
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(event, now: coreExpiry.addingTimeInterval(1)), .expired(.appStoreConnectJWT, at: coreExpiry))
    }

    func testLongLivedCredentialsAreNeverIncludable() {
        for kind in [NetworkAuditCredentialInfo.Kind.appleSessionCookie, .oauthAssertion, .other] {
            let resolved = NetworkAuditRecorder.resolveCredential(hint: .known(kind, expiresAt: now.addingTimeInterval(600)), decoded: nil)
            XCTAssertEqual(resolved?.kind, kind)
            XCTAssertNil(resolved?.expiresAt)
            XCTAssertFalse(resolved?.isShortLived ?? true)
        }
        XCTAssertNil(NetworkAuditRecorder.resolveCredential(hint: .unauthenticated, decoded: nil))
    }

    func testAppleSessionEventIsNotExportableWithAToken() throws {
        let event = try makeEvent(entry(
            provider: .appleWebSession,
            credentialKind: .appleSessionCookie,
            url: "https://appstoreconnect.apple.com/iris/v1/apps",
            requestHeaders: [.init(name: "Authorization", value: "Bearer abc"), .init(name: "X-Csrf-Itc", value: "itc")]
        ))

        XCTAssertEqual(event.credential?.kind, .appleSessionCookie)
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(event, now: now), .alwaysMasked)
    }

    func testCredentialKindMapping() {
        XCTAssertEqual(NetworkAuditCoreEntryMapper.credential(.ascJwt, expiresAtMs: 1_000), .known(.appStoreConnectJWT, expiresAt: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(NetworkAuditCoreEntryMapper.credential(.googleAccessToken, expiresAtMs: nil), .known(.googleAccessToken, expiresAt: nil))
        XCTAssertEqual(NetworkAuditCoreEntryMapper.credential(.appleSessionCookie, expiresAtMs: 5), .known(.appleSessionCookie, expiresAt: nil))
        XCTAssertEqual(NetworkAuditCoreEntryMapper.credential(.oauthAssertion, expiresAtMs: 5), .known(.oauthAssertion, expiresAt: nil))
        XCTAssertEqual(NetworkAuditCoreEntryMapper.credential(.unauthenticated, expiresAtMs: nil), .unauthenticated)
    }

    // MARK: - Account names

    private struct StubResolver: NetworkAuditAccountResolving {
        func accountName(forCoreAccountId id: String) async -> String? {
            id == "69a6de70-issuer" ? "My Company" : nil
        }
    }

    func testAccountIdResolvesToTheAccountName() async throws {
        let recorder = NetworkAuditRecorder(store: store, settings: settings, vault: vault, accounts: StubResolver(), now: { NetworkAuditFixtures.now })
        let (exchange, annotations) = try XCTUnwrap(NetworkAuditCoreEntryMapper.map(entry()))
        let (unknownExchange, unknownAnnotations) = try XCTUnwrap(NetworkAuditCoreEntryMapper.map(entry(accountId: "someone-else")))

        await recorder.persistCore(exchange, annotations: annotations)
        await recorder.persistCore(unknownExchange, annotations: unknownAnnotations)

        let events = await store.events
        XCTAssertEqual(events.map(\.accountName), ["My Company", nil])
    }

    func testAccountDirectoryJoinsSharedIdsAndRefreshes() async {
        nonisolated(unsafe) var accounts: [(id: String, name: String, provider: ProviderType)] = [
            ("a1", "Team One", .apple), ("a2", "Team Two", .apple), ("g1", "Play", .googlePlay)
        ]
        let directory = NetworkAuditAccountDirectory(
            loadAccounts: { accounts },
            credentialIds: { id, _ in id == "g1" ? ["bot@project.iam.gserviceaccount.com"] : ["Me@Example.com"] }
        )

        let shared = await directory.accountName(forCoreAccountId: "me@example.com")
        let play = await directory.accountName(forCoreAccountId: "bot@project.iam.gserviceaccount.com")
        XCTAssertEqual(shared, "Team One, Team Two")
        XCTAssertEqual(play, "Play")

        accounts = [("g1", "Renamed", .googlePlay)]
        let cached = await directory.accountName(forCoreAccountId: "bot@project.iam.gserviceaccount.com")
        XCTAssertEqual(cached, "Play")
        await directory.invalidate()
        let refreshed = await directory.accountName(forCoreAccountId: "bot@project.iam.gserviceaccount.com")
        XCTAssertEqual(refreshed, "Renamed")
    }

    func testCoreIdsFromStoredCredentials() {
        let keychain = MockKeyStorable()
        keychain.setObject(AppleCredentials(issuerID: "ISSUER", privateKeyID: "K", privateKey: "P"), forKey: "credentials.a1")
        keychain.setObject(GooglePlayCredentials(googleLoginId: "LOGIN"), forKey: "credentials.g1")

        XCTAssertEqual(NetworkAuditAccountDirectory.coreIds(accountId: "a1", provider: .apple, keychain: keychain), ["ISSUER"])
        XCTAssertEqual(NetworkAuditAccountDirectory.coreIds(accountId: "g1", provider: .googlePlay, keychain: keychain), ["LOGIN"])
        XCTAssertEqual(NetworkAuditAccountDirectory.coreIds(accountId: "missing", provider: .apple, keychain: keychain), [])
    }

    // MARK: - Sink and factory

    private final class CapturingRecorder: NetworkAuditCoreRecording, @unchecked Sendable {
        private(set) var recorded: [(NetworkAuditExchange, NetworkAuditAnnotations)] = []
        func recordCore(_ exchange: NetworkAuditExchange, annotations: NetworkAuditAnnotations) {
            recorded.append((exchange, annotations))
        }
    }

    func testSinkHandsEntriesToTheRecorderAndFollowsFullBodies() {
        let capturing = CapturingRecorder()
        let sink = NetworkAuditCoreSink(recorder: capturing, settings: settings)

        sink.record(entry: entry())

        XCTAssertEqual(capturing.recorded.count, 1)
        XCTAssertEqual(capturing.recorded.first?.0.source, .rustCore)
        XCTAssertTrue(sink.captureBodies())
        settings.recordsFullBodies = false
        XCTAssertFalse(sink.captureBodies())
    }

    private func flags(networkAudit: Bool) -> (FeatureFlags, UserDefaults, String) {
        let suite = "NetworkAuditCoreSinkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(networkAudit, forKey: FeatureFlag.networkAudit.rawValue)
        return (FeatureFlags(defaults: defaults, remoteValues: StubRemoteFeatureValues()), defaults, suite)
    }

    func testNoSinkWhenTheFlagIsOff() {
        let (off, defaults, suite) = flags(networkAudit: false)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(NetworkAuditCoreSinkFactory.make(featureFlags: off, recorder: recorder))
    }

    func testNoSinkWithoutAnInstalledRecorder() {
        let (on, defaults, suite) = flags(networkAudit: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(NetworkAuditCoreSinkFactory.make(featureFlags: on, recorder: nil))
        // The unit-test host never installs the capture.
        XCTAssertNil(NetworkAuditCoreSinkFactory.make(featureFlags: on))
    }

    func testOneSharedSinkWhileOn() {
        let (on, defaults, suite) = flags(networkAudit: true)
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = NetworkAuditCoreSinkFactory.make(featureFlags: on, recorder: recorder)
        let second = NetworkAuditCoreSinkFactory.make(featureFlags: on, recorder: recorder)

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
    }
}
