import XCTest
import StackProtocols
@testable import StackConnect

/// StackConnect's own telemetry (Firebase SDKs): its keys and tokens belong to
/// the app's Firebase project and are never shown, revealed, copied in clear
/// or exported. The user's own Firebase / Google accounts keep the reveal.
@MainActor
final class NetworkAuditAppTelemetryTests: XCTestCase {

    private let now = NetworkAuditFixtures.now
    private let apiKey = "AIzaSyD1234567890abcdefghijklmnopqrstuv"
    private let appBundleId = "zeroSixteen.stackconnect"
    private let projectId = "stack-connect-88e17"
    private let googleAppId = "1:123456789012:ios:abcdef0123456789"
    private let oauthClientId = "123456789012-oauthclient.apps.googleusercontent.com"
    private var identity: NetworkAuditAppIdentity {
        NetworkAuditAppIdentity(
            bundleIds: [appBundleId],
            firebaseValues: [projectId, "123456789012", googleAppId, apiKey],
            oauthClientIds: [oauthClientId]
        )
    }
    private let fisToken = "eyJhbGciOiJFUzI1NiJ9.FISAUTHTOKENPAYLOAD.sig"
    private var keychain: MockKeyStorable!
    private var vault: NetworkAuditSecretVault!
    private var recorder: NetworkAuditRecorder!

    override func setUp() {
        super.setUp()
        keychain = MockKeyStorable()
        vault = NetworkAuditSecretVault(keychain: keychain)
        recorder = NetworkAuditRecorder(store: MockNetworkAuditStore(), settings: MockNetworkAuditSettings(), vault: vault, appIdentity: identity, now: { NetworkAuditFixtures.now })
    }

    // MARK: - Fixtures

    private var installationsExchange: NetworkAuditExchange {
        NetworkAuditFixtures.exchange(
            url: "https://firebaseinstallations.googleapis.com/v1/projects/stack-connect/installations/FID123/authTokens:generate?key=\(apiKey)",
            method: "POST",
            authorization: "FIS_v2 \(fisToken)",
            requestHeaders: [
                .init(name: "x-goog-api-key", value: apiKey),
                .init(name: "X-Ios-Bundle-Identifier", value: "zeroSixteen.stackconnect"),
                .init(name: "X-Ios-Device-Model", value: "iPhone17,2"),
                .init(name: "x-firebase-client", value: "apple-platform/ios fire-install/11.0.0"),
                .init(name: "Content-Type", value: "application/json")
            ],
            requestBody: Data(#"{"installation":{"sdkVersion":"i:11.0.0","appId":"1:123456789012:ios:abcdef0123456789"}}"#.utf8),
            responseBody: Data(#"{"name":"projects/1/installations/FID123","fid":"FID123","refreshToken":"REFRESHSECRET","authToken":{"token":"AUTHTOKENSECRET","expiresIn":"604800s"}}"#.utf8)
        )
    }

    private var remoteConfigExchange: NetworkAuditExchange {
        NetworkAuditFixtures.exchange(
            url: "https://firebaseremoteconfig.googleapis.com/v1/projects/stack-connect-88e17/namespaces/firebase:fetch",
            method: "POST",
            requestHeaders: [
                .init(name: "X-Goog-Api-Key", value: apiKey),
                .init(name: "X-Goog-Firebase-Installations-Auth", value: fisToken),
                .init(name: "X-Firebase-AppCheck", value: "APPCHECKSECRET"),
                .init(name: "Content-Type", value: "application/json")
            ],
            requestBody: Data(#"{"appInstanceId":"FID123","appInstanceIdToken":"INSTANCETOKENSECRET","appId":"1:123456789012:ios:abcdef0123456789","sdkVersion":"11.0.0","platformVersion":"26.1"}"#.utf8)
        )
    }

    /// The user's own Firebase project (Firebase Management with their token).
    private var userFirebaseExchange: NetworkAuditExchange {
        NetworkAuditFixtures.exchange(
            url: "https://firebase.googleapis.com/v1beta1/projects?pageSize=100",
            authorization: "Bearer ya29.a0AfB_user_token_123"
        )
    }

    private func encoded(_ event: NetworkAuditEvent) throws -> String {
        String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
    }

    private let secrets = [
        "AIzaSyD1234567890", "FISAUTHTOKENPAYLOAD", "REFRESHSECRET", "AUTHTOKENSECRET",
        "APPCHECKSECRET", "INSTANCETOKENSECRET", "zeroSixteen.stackconnect", "stack-connect-88e17",
        "1:123456789012:ios"
    ]

    private func assertNoSecrets(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for secret in secrets {
            XCTAssertFalse(text.contains(secret), secret, file: file, line: line)
        }
    }

    // MARK: - Storage

    func testInstallationsSecretsAreMaskedAndNeverSealed() throws {
        let event = recorder.makeEvent(from: installationsExchange)

        XCTAssertEqual(event.category, .telemetry)
        XCTAssertTrue(event.isAppTelemetry)
        XCTAssertNil(event.sealedSecrets)
        XCTAssertNil(event.credential)
        XCTAssertNil(keychain.data(forKey: NetworkAuditSecretVault.keychainKey), "no vault key is even created")
        assertNoSecrets(try encoded(event))

        let auth = try XCTUnwrap(event.requestHeaders.first { $0.name == "Authorization" })
        XCTAssertEqual(auth.value, "FIS_v2 [MASKED]")
        XCTAssertEqual(auth.maskedPreview, "FIS_v2 ••••••••", "no characters of the token in the preview")
        XCTAssertEqual(event.requestHeaders.first { $0.name == "x-goog-api-key" }?.value, "[MASKED]")
        XCTAssertTrue(event.url?.contains("key=[MASKED]") ?? false)

        // StackConnect's own bundle ID is app data; the device stays visible.
        let bundleHeader = try XCTUnwrap(event.requestHeaders.first { $0.name == "X-Ios-Bundle-Identifier" })
        XCTAssertEqual(bundleHeader.value, "[APP]")
        XCTAssertEqual(bundleHeader.isAppData, true)
        XCTAssertEqual(event.requestHeaders.first { $0.name == "X-Ios-Device-Model" }?.value, "iPhone17,2")
        XCTAssertTrue(event.requestBody.text?.contains("\"appId\" : \"[APP]\"") ?? false)
        XCTAssertEqual(event.hidesAppData, true)
        XCTAssertTrue(event.hidesAppValues)
        XCTAssertEqual(event.requestHeaders.first { $0.name == "x-firebase-client" }?.isSecret, false)
        XCTAssertTrue(event.requestBody.text?.contains("i:11.0.0") ?? false)
        XCTAssertTrue(event.responseBody.text?.contains("\"fid\" : \"FID123\"") ?? false)
    }

    func testRemoteConfigFetchSecretsAreMasked() throws {
        let event = recorder.makeEvent(from: remoteConfigExchange)

        XCTAssertTrue(event.isAppTelemetry)
        XCTAssertNil(event.sealedSecrets)
        assertNoSecrets(try encoded(event))
        for name in ["X-Goog-Api-Key", "X-Goog-Firebase-Installations-Auth", "X-Firebase-AppCheck"] {
            XCTAssertEqual(event.requestHeaders.first { $0.name == name }?.isSecret, true, name)
        }
        XCTAssertEqual(event.path, "/v1/projects/[APP]/namespaces/firebase:fetch")
        XCTAssertTrue(event.url?.contains("/projects/[APP]/namespaces") ?? false)
        XCTAssertTrue(event.requestBody.text?.contains("\"appId\" : \"[APP]\"") ?? false)
        XCTAssertTrue(event.requestBody.text?.contains("\"platformVersion\" : \"26.1\"") ?? false)
        XCTAssertTrue(event.requestBody.text?.contains("\"appInstanceId\" : \"FID123\"") ?? false, "the installation of this device stays visible")
    }

    func testUserOwnedFirebaseKeepsTheReveal() throws {
        let event = recorder.makeEvent(from: userFirebaseExchange)

        XCTAssertEqual(event.category, .google)
        XCTAssertFalse(event.isAppTelemetry)
        let sealed = try XCTUnwrap(event.sealedSecrets)
        XCTAssertEqual(vault.open(sealed)?.values.first, "Bearer ya29.a0AfB_user_token_123")
        XCTAssertEqual(event.credential?.kind, .googleAccessToken)
        XCTAssertNil(event.appTelemetrySanitized())
    }

    func testCoreFirebaseProviderIsTheUsersAccount() throws {
        let entry = NetworkAuditFixtures.exchange(url: "https://firebase.googleapis.com/v1beta1/projects", authorization: "Bearer ya29.core_user_token_1234")
        let event = recorder.makeEvent(from: entry, annotations: NetworkAuditAnnotations(category: .google, credential: .known(.googleAccessToken, expiresAt: nil)))

        XCTAssertFalse(event.isAppTelemetry)
        XCTAssertNotNil(event.sealedSecrets)
    }

    // MARK: - Legacy data

    /// An event an older version stored: telemetry host categorized "Other"
    /// (or Telemetry), with the original sealed and a token prefix in the preview.
    private func legacyTelemetryEvent(category: NetworkAuditCategory) -> NetworkAuditEvent {
        let oldRecorder = NetworkAuditRecorder(store: MockNetworkAuditStore(), settings: MockNetworkAuditSettings(), vault: vault, appIdentity: .empty, now: { NetworkAuditFixtures.now })
        var event = oldRecorder.makeEvent(
            from: NetworkAuditFixtures.exchange(
                url: "https://app-analytics-services.com/sdk-exp?app=zeroSixteen.stackconnect",
                method: "POST",
                authorization: "FIS_v2 \(fisToken)",
                requestHeaders: [.init(name: "X-Ios-Bundle-Identifier", value: "zeroSixteen.stackconnect")]
            ),
            annotations: NetworkAuditAnnotations(category: .other)
        )
        event.category = category
        return event
    }

    func testLegacySealedTelemetryIsDroppedOnScrub() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppTelemetryScrub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileNetworkAuditStore(directory: directory)
        let recorder = NetworkAuditRecorder(store: store, settings: MockNetworkAuditSettings(), vault: vault, appIdentity: identity, now: { NetworkAuditFixtures.now })
        let legacyOther = legacyTelemetryEvent(category: .other)
        let legacyTelemetry = legacyTelemetryEvent(category: .telemetry)
        let user = recorder.makeEvent(from: userFirebaseExchange)
        XCTAssertNotNil(legacyOther.sealedSecrets)
        XCTAssertTrue(legacyOther.requestHeaders.contains { $0.maskedPreview?.contains("eyJhbG") == true })
        for event in [legacyOther, legacyTelemetry, user] {
            await store.append(event)
        }

        let rewritten = await recorder.scrubAppTelemetrySecrets()
        let again = await recorder.scrubAppTelemetrySecrets()

        XCTAssertEqual(rewritten, 2)
        XCTAssertEqual(again, 0)
        for legacy in [legacyOther, legacyTelemetry] {
            let stored = await store.event(for: legacy.summary)
            XCTAssertNil(stored?.sealedSecrets)
            XCTAssertEqual(stored?.category, .telemetry)
            XCTAssertFalse(stored?.requestHeaders.contains { $0.maskedPreview?.contains("eyJhbG") == true } ?? true)
            XCTAssertEqual(stored?.path, "/sdk-exp?app=[APP]")
            XCTAssertEqual(stored?.requestHeaders.first { $0.name == "X-Ios-Bundle-Identifier" }?.value, "[APP]")
            let summaries = await store.summaries(since: .distantPast)
            XCTAssertEqual(summaries.first { $0.id == legacy.id }?.path, "/sdk-exp?app=[APP]", "the list index is rewritten too")
        }
        let storedUser = await store.event(for: user.summary)
        XCTAssertNotNil(storedUser?.sealedSecrets, "the user's own secrets stay revealable")
    }

    func testDetailNeverOffersARevealForLegacyTelemetry() async throws {
        let legacy = legacyTelemetryEvent(category: .other)
        let authenticator = MockNetworkAuditAuthenticator(result: true)
        let pasteboard = MockNetworkAuditPasteboard()
        var dependencies = NetworkAuditFixtures.dependencies(store: MockNetworkAuditStore(events: [legacy]), vault: vault,
                                                             authenticator: authenticator, pasteboard: pasteboard)
        dependencies.appIdentity = identity
        let sut = NetworkAuditDetailViewModel(summary: legacy.summary, dependencies: dependencies)

        await sut.load()
        await sut.toggleSecrets()
        XCTAssertTrue(sut.uiState.hidesAppValues)
        XCTAssertEqual(sut.uiState.headers.first { $0.name == "X-Ios-Bundle-Identifier" }?.isAppData, true)
        XCTAssertFalse(sut.uiState.event?.url?.contains("zeroSixteen.stackconnect") ?? true)

        XCTAssertTrue(sut.uiState.isAppTelemetry)
        XCTAssertFalse(sut.uiState.canRevealSecrets)
        XCTAssertFalse(sut.uiState.isRevealed)
        XCTAssertTrue(authenticator.reasons.isEmpty, "Face ID is never even asked")
        XCTAssertNil(sut.uiState.event?.sealedSecrets)
        let header = try XCTUnwrap(sut.uiState.headers.first { $0.name == "Authorization" })
        XCTAssertEqual(header.displayValue, "FIS_v2 ••••••••")
        sut.copyHeader(header)
        XCTAssertEqual(pasteboard.copies.last?.text, "Authorization: FIS_v2 [MASKED]")
        XCTAssertEqual(pasteboard.copies.last?.sensitive, false)
    }

    func testDetailKeepsTheRevealForTheUsersFirebase() async {
        let event = recorder.makeEvent(from: userFirebaseExchange)
        let sut = NetworkAuditDetailViewModel(
            summary: event.summary,
            dependencies: NetworkAuditFixtures.dependencies(store: MockNetworkAuditStore(events: [event]), vault: vault)
        )

        await sut.load()
        await sut.toggleSecrets()

        XCTAssertFalse(sut.uiState.isAppTelemetry)
        XCTAssertTrue(sut.uiState.canRevealSecrets)
        XCTAssertTrue(sut.uiState.isRevealed)
    }

    // MARK: - Export

    func testSingleEventExportNeverIncludesAnAppToken() async {
        let legacy = legacyTelemetryEvent(category: .telemetry)
        let authenticator = MockNetworkAuditAuthenticator(result: true)
        let pasteboard = MockNetworkAuditPasteboard()
        let sut = NetworkAuditEventExportViewModel(
            summary: legacy.summary,
            dependencies: NetworkAuditFixtures.dependencies(store: MockNetworkAuditStore(events: [legacy]), vault: vault,
                                                            authenticator: authenticator, pasteboard: pasteboard)
        )

        await sut.load()
        await sut.setIncludeRealToken(true)
        sut.copy()

        XCTAssertTrue(sut.uiState.isAppTelemetry)
        XCTAssertEqual(sut.uiState.tokenInclusion, .appTelemetry)
        XCTAssertFalse(sut.uiState.canToggleToken)
        XCTAssertFalse(sut.uiState.includesRealToken)
        XCTAssertTrue(authenticator.reasons.isEmpty)
        XCTAssertEqual(sut.uiState.secretNote, NetworkAuditAppSecretCopy.exportNote)
        XCTAssertFalse(pasteboard.copies.last?.text.contains("FISAUTHTOKENPAYLOAD") ?? true)
    }

    func testEveryFormatKeepsTelemetrySecretsMasked() {
        let exporter = NetworkAuditExporter(appVersion: "2.4.0", timeZone: TimeZone(identifier: "UTC")!)
        let events = [recorder.makeEvent(from: installationsExchange), recorder.makeEvent(from: remoteConfigExchange)]

        for format in NetworkAuditBatchFormat.allCases {
            assertNoSecrets(exporter.batch(events, format: format, includeBodies: true))
        }
        for format in NetworkAuditEventFormat.allCases {
            for event in events {
                assertNoSecrets(exporter.single(event, format: format, includeBody: true))
            }
        }
    }

    func testBatchExportListsAppTelemetrySecrets() {
        XCTAssertTrue(NetworkAuditMaskedSecretsSection.items.contains(NetworkAuditAppSecretCopy.maskedListItem))
    }

    func testTokenInclusionForTelemetry() {
        let event = recorder.makeEvent(from: installationsExchange)
        let noSecrets = recorder.makeEvent(from: NetworkAuditFixtures.exchange(url: "https://app-measurement.com/a", method: "POST"))

        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(event, now: now), .appTelemetry)
        XCTAssertFalse(NetworkAuditTokenInclusion.appTelemetry.canInclude)
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(noSecrets, now: now), .notApplicable)
    }

    // MARK: - App identity

    func testUserAccountTrafficKeepsBundleIdsButHidesTheOAuthClient() throws {
        // The developer's own App Store Connect app list may contain
        // StackConnect itself: that is the user's data and stays visible.
        let asc = recorder.makeEvent(from: NetworkAuditFixtures.exchange(
            url: "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=zeroSixteen.stackconnect",
            responseBody: Data(#"{"data":[{"attributes":{"bundleId":"zeroSixteen.stackconnect"}},{"attributes":{"bundleId":"com.user.app"}}]}"#.utf8)
        ))
        XCTAssertTrue(asc.path.contains("zeroSixteen.stackconnect"))
        XCTAssertTrue(asc.responseBody.text?.contains("com.user.app") ?? false)
        XCTAssertTrue(asc.responseBody.text?.contains("zeroSixteen.stackconnect") ?? false)
        XCTAssertNil(asc.hidesAppData)
        XCTAssertFalse(asc.hidesAppValues)

        let firebaseManagement = recorder.makeEvent(from: NetworkAuditFixtures.exchange(
            url: "https://firebase.googleapis.com/v1beta1/projects/stack-connect-88e17/iosApps"
        ))
        XCTAssertTrue(firebaseManagement.path.contains("stack-connect-88e17"), "the user's own Firebase project stays visible")

        // The Google sign-in token exchange: the app's OAuth client is hidden,
        // the user's token stays revealable.
        let oauth = recorder.makeEvent(from: NetworkAuditFixtures.exchange(
            url: "https://oauth2.googleapis.com/token",
            method: "POST",
            authorization: "Bearer ya29.a0AfB_user_token_456",
            requestHeaders: [.init(name: "Content-Type", value: "application/x-www-form-urlencoded")],
            requestBody: Data("grant_type=authorization_code&client_id=\(oauthClientId)&redirect_uri=com.googleusercontent.apps.123456789012-oauthclient%3A%2Foauth2redirect".utf8)
        ))
        let body = try XCTUnwrap(oauth.requestBody.text)
        XCTAssertFalse(body.contains("oauthclient"))
        XCTAssertTrue(body.contains("client_id=[APP]"))
        XCTAssertTrue(body.contains("redirect_uri=[APP]%3A%2Foauth2redirect"))
        XCTAssertEqual(oauth.hidesAppData, true)
        XCTAssertNotNil(oauth.sealedSecrets, "the user's token is still revealable")
    }

    func testIdentityMasksPercentEncodedValues() {
        let (masked, didMask) = identity.mask("x?app=1%3A123456789012%3Aios%3Aabcdef0123456789&b=2", isUserAccountTraffic: false)

        XCTAssertTrue(didMask)
        XCTAssertEqual(masked, "x?app=[APP]&b=2")
    }

    func testIdentityLoadsFromTheBundle() {
        let loaded = NetworkAuditAppIdentity.load(bundle: .main)
        if let bundleId = Bundle.main.bundleIdentifier {
            XCTAssertTrue(loaded.appTrafficValues.contains(bundleId))
        }
        XCTAssertTrue(NetworkAuditAppIdentity(bundleIds: ["short"], firebaseValues: [], oauthClientIds: []).isEmpty, "values under 6 characters are ignored")
    }

    func testNoCardWhenNothingWasHidden() {
        let plain = recorder.makeEvent(from: NetworkAuditFixtures.exchange(url: "https://app-measurement.com/a", method: "POST"))

        XCTAssertFalse(plain.hidesAppValues)
        XCTAssertTrue(recorder.makeEvent(from: installationsExchange).hidesAppValues)
    }

    func testListSummariesOfLegacyEventsHideAppValues() async {
        let legacy = legacyTelemetryEvent(category: .other)
        var dependencies = NetworkAuditFixtures.dependencies(store: MockNetworkAuditStore(events: [legacy]))
        dependencies.appIdentity = identity
        let sut = NetworkAuditViewModel(dependencies: dependencies, calendar: NetworkAuditFixtures.utcCalendar)

        await sut.load()

        let row = sut.uiState.groups.first?.events.first
        XCTAssertEqual(row?.path, "/sdk-exp?app=[APP]")
        XCTAssertEqual(row?.category, .telemetry)
    }
}
