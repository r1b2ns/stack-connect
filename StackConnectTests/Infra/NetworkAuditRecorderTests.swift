import XCTest
import StackProtocols
@testable import StackConnect

final class NetworkAuditRecorderTests: XCTestCase {

    private var store: MockNetworkAuditStore!
    private var settings: MockNetworkAuditSettings!
    private var keychain: MockKeyStorable!
    private var vault: NetworkAuditSecretVault!
    private var sut: NetworkAuditRecorder!

    override func setUp() {
        super.setUp()
        store = MockNetworkAuditStore()
        settings = MockNetworkAuditSettings()
        keychain = MockKeyStorable()
        vault = NetworkAuditSecretVault(keychain: keychain)
        sut = NetworkAuditRecorder(store: store, settings: settings, vault: vault, now: { NetworkAuditFixtures.now })
    }

    // MARK: - Masking at capture

    func testAuthorizationIsMaskedAndSealed() throws {
        let token = NetworkAuditFixtures.ascJWT(expiresAt: NetworkAuditFixtures.now.addingTimeInterval(600))

        let event = sut.makeEvent(from: NetworkAuditFixtures.exchange(authorization: "Bearer \(token)"))

        let header = try XCTUnwrap(event.requestHeaders.first { $0.name == "Authorization" })
        XCTAssertEqual(header.value, "Bearer [MASKED]")
        XCTAssertTrue(header.isSecret)
        XCTAssertEqual(event.credential?.kind, .appStoreConnectJWT)
        let index = try XCTUnwrap(event.requestHeaders.firstIndex(of: header))
        let secrets = try XCTUnwrap(vault.open(try XCTUnwrap(event.sealedSecrets)))
        XCTAssertEqual(secrets[NetworkAuditRecorder.secretKey(request: true, index: index)], "Bearer \(token)")
        XCTAssertNotNil(keychain.data(forKey: NetworkAuditSecretVault.keychainKey))
    }

    func testEventWithoutSecretsHasNoSealedBox() {
        let event = sut.makeEvent(from: NetworkAuditFixtures.exchange())

        XCTAssertNil(event.sealedSecrets)
        XCTAssertNil(event.credential)
    }

    func testMetadataCategoryAndPurpose() {
        let event = sut.makeEvent(from: NetworkAuditFixtures.exchange())

        XCTAssertEqual(event.kind, .http)
        XCTAssertEqual(event.method, "GET")
        XCTAssertEqual(event.host, "api.appstoreconnect.apple.com")
        XCTAssertEqual(event.path, "/v1/apps?limit=200&include=appStoreVersions")
        XCTAssertEqual(event.category, .apple)
        XCTAssertEqual(event.connection, "TLS 1.3 · HTTP/2")
        XCTAssertEqual(event.statusCode, 200)
        XCTAssertTrue(event.isSuccess)
        XCTAssertNotNil(event.purpose)
    }

    func testSecretsInURLAndBodiesNeverReachTheEvent() throws {
        let exchange = NetworkAuditFixtures.exchange(
            url: "https://oauth2.googleapis.com/token?key=AIzaSECRETKEY",
            method: "POST",
            requestHeaders: [.init(name: "Content-Type", value: "application/x-www-form-urlencoded")],
            requestBody: Data("grant_type=refresh_token&refresh_token=1%2F%2FREFRESHSECRET".utf8),
            responseBody: Data(#"{"access_token":"ya29.ACCESSSECRET","expires_in":3599,"id_token":"IDSECRET"}"#.utf8)
        )

        let event = sut.makeEvent(from: exchange)
        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)

        for secret in ["AIzaSECRETKEY", "REFRESHSECRET", "ACCESSSECRET", "IDSECRET"] {
            XCTAssertFalse(encoded.contains(secret), secret)
        }
        XCTAssertEqual(event.category, .google)
        XCTAssertEqual(event.requestBody.text, "grant_type=refresh_token&refresh_token=[MASKED]")
    }

    func testTokenResponseGivesLaterGoogleRequestsAnExpiry() {
        let tokenResponse = NetworkAuditFixtures.exchange(
            url: "https://oauth2.googleapis.com/token",
            method: "POST",
            responseBody: Data(#"{"access_token":"ya29.a0AfB_live_token","expires_in":3600}"#.utf8)
        )
        _ = sut.makeEvent(from: tokenResponse)

        let apiCall = sut.makeEvent(from: NetworkAuditFixtures.exchange(
            url: "https://firebase.googleapis.com/v1beta1/projects",
            authorization: "Bearer ya29.a0AfB_live_token"
        ))

        XCTAssertEqual(apiCall.credential?.kind, .googleAccessToken)
        XCTAssertEqual(
            apiCall.credential?.expiresAt?.timeIntervalSince1970 ?? 0,
            NetworkAuditFixtures.now.addingTimeInterval(0.412 + 3600).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testFullBodiesOffKeepsOnlySizes() {
        settings.recordsFullBodies = false

        let event = sut.makeEvent(from: NetworkAuditFixtures.exchange())

        XCTAssertEqual(event.responseBody.content, .notRecorded)
        XCTAssertGreaterThan(event.responseBody.byteCount, 0)
        XCTAssertFalse(event.requestHeaders.isEmpty)
    }

    func testBinaryBodyIsDescribedOnly() {
        let event = sut.makeEvent(from: NetworkAuditFixtures.exchange(
            responseHeaders: [.init(name: "Content-Type", value: "image/png")],
            responseBody: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01])
        ))

        XCTAssertEqual(event.responseBody.content, .binary)
        XCTAssertEqual(event.responseBody.byteCount, 6)
    }

    func testLongBodyIsTruncatedAfterMasking() {
        let long = String(repeating: "a", count: NetworkAuditRecorder.maxBodyBytes + 10)
        let event = sut.makeEvent(from: NetworkAuditFixtures.exchange(
            responseHeaders: [.init(name: "Content-Type", value: "text/plain")],
            responseBody: Data(long.utf8)
        ))

        XCTAssertTrue(event.responseBody.isTruncated)
        XCTAssertEqual(event.responseBody.text?.utf8.count, NetworkAuditRecorder.maxBodyBytes)
    }

    func testFailedRequestIsAnError() {
        let event = sut.makeEvent(from: NetworkAuditFixtures.exchange(status: nil, responseBody: nil, error: "The Internet connection appears to be offline."))

        XCTAssertFalse(event.isSuccess)
        XCTAssertEqual(event.summary.isSuccess, false)
    }

    // MARK: - Persistence and local events

    func testPersistStoresTheEvent() async {
        await sut.persist(NetworkAuditFixtures.exchange())

        let events = await store.events
        XCTAssertEqual(events.count, 1)
    }

    func testExportEventDescribesTheExport() {
        let event = sut.makeExportEvent(NetworkAuditExportRecord(
            formatName: "cURL",
            subject: "GET api.appstoreconnect.apple.com/v1/apps",
            action: .copied,
            includesRealToken: true,
            byteCount: 512
        ))

        XCTAssertEqual(event.kind, .export)
        XCTAssertEqual(event.category, .local)
        XCTAssertEqual(event.method, "EXPORT")
        XCTAssertEqual(event.host, String(localized: "\("cURL") with token"))
        XCTAssertEqual(event.statusText, String(localized: "Face ID"))
        XCTAssertEqual(event.bytesSent, 512)
        XCTAssertTrue(event.isSuccess)
    }

    func testMaskedExportWithoutTokenSaysCopied() {
        let event = sut.makeExportEvent(NetworkAuditExportRecord(formatName: "JSON", subject: "3 events · Today", action: .copied, includesRealToken: false, byteCount: 10))

        XCTAssertEqual(event.host, String(localized: "\("JSON") export"))
        XCTAssertEqual(event.statusText, String(localized: "Copied"))
    }

    func testMaskedFileNames() {
        XCTAssertEqual(NetworkAuditRecorder.maskedFileName("AuthKey_2X9B4K7Q3Z.p8"), "AuthKey_••••.p8")
        XCTAssertEqual(NetworkAuditRecorder.maskedFileName("my-project-a1b2c3.json"), "••••.json")
    }

    func testPurgeExpiredUsesTheRetention() async {
        settings.retention = .sevenDays

        await sut.purgeExpired()

        let cutoffs = await store.purgeCutoffs
        XCTAssertEqual(cutoffs, [NetworkAuditRetention.sevenDays.cutoff(from: NetworkAuditFixtures.now)])
    }

    func testDeleteAllDropsTheKey() async {
        _ = vault.seal(["request.0": "Bearer x"])
        XCTAssertNotNil(keychain.data(forKey: NetworkAuditSecretVault.keychainKey))

        await sut.deleteAll()

        let deletes = await store.deleteAllCount
        XCTAssertEqual(deletes, 1)
        XCTAssertNil(keychain.data(forKey: NetworkAuditSecretVault.keychainKey))
    }

    // MARK: - Vault

    func testVaultDoesNotCreateAKeyWhileTheKeychainIsLocked() {
        keychain.isUnavailable = true

        XCTAssertNil(vault.seal(["request.0": "Bearer x"]))
        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    func testSealedBoxCantBeOpenedWithAnotherKey() throws {
        let sealed = try XCTUnwrap(vault.seal(["request.0": "Bearer x"]))
        let otherVault = NetworkAuditSecretVault(keychain: MockKeyStorable())
        _ = otherVault.seal(["x": "y"])

        XCTAssertNil(otherVault.open(sealed))
        XCTAssertEqual(vault.open(sealed), ["request.0": "Bearer x"])
    }
}

// MARK: - URLProtocol

final class NetworkAuditURLProtocolTests: XCTestCase {

    private final class NullSink: NetworkAuditExchangeSink {
        func record(_ exchange: NetworkAuditExchange) {}
    }

    override func tearDown() {
        NetworkAuditURLProtocol.sink = nil
        super.tearDown()
    }

    func testDoesNothingWithoutASink() {
        NetworkAuditURLProtocol.sink = nil

        XCTAssertFalse(NetworkAuditURLProtocol.canInit(with: URLRequest(url: URL(string: "https://example.com")!)))
    }

    func testHandlesHTTPOnceOnly() {
        NetworkAuditURLProtocol.sink = NullSink()
        let request = URLRequest(url: URL(string: "https://example.com/a")!)

        XCTAssertTrue(NetworkAuditURLProtocol.canInit(with: request))
        XCTAssertFalse(NetworkAuditURLProtocol.canInit(with: URLRequest(url: URL(string: "file:///tmp/a")!)))
        // The forwarded copy is marked: never recorded a second time.
        XCTAssertFalse(NetworkAuditURLProtocol.canInit(with: NetworkAuditURLProtocol.forwardedRequest(for: request)))
    }

    func testForwardedRequestReadsAStreamedBody() {
        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        request.httpMethod = "POST"
        request.httpBodyStream = InputStream(data: Data("payload".utf8))

        let forwarded = NetworkAuditURLProtocol.forwardedRequest(for: request)

        XCTAssertEqual(forwarded.httpBody, Data("payload".utf8))
        XCTAssertNil(forwarded.httpBodyStream)
        XCTAssertEqual(forwarded.httpMethod, "POST")
    }

    func testTagsRideOnTheRequestWithoutHeaders() {
        let tagged = NetworkAuditRequestTag.tagged(
            URLRequest(url: URL(string: "https://example.com")!),
            origin: "Home · pull to refresh",
            purpose: "Sync the app list",
            account: "My Company"
        )

        let tags = NetworkAuditRequestTag.tags(of: tagged)
        XCTAssertEqual(tags.origin, "Home · pull to refresh")
        XCTAssertEqual(tags.purpose, "Sync the app list")
        XCTAssertEqual(tags.account, "My Company")
        XCTAssertNil(tagged.allHTTPHeaderFields?.values.first { $0.contains("Home") })
    }

    func testInjectPutsTheRecorderFirstOnce() {
        let configuration = URLSessionConfiguration.ephemeral
        NetworkAuditSessionInstaller.inject(into: configuration)
        NetworkAuditSessionInstaller.inject(into: configuration)

        let classes = configuration.protocolClasses ?? []
        XCTAssertTrue(classes.first == NetworkAuditURLProtocol.self)
        XCTAssertEqual(classes.filter { $0 == NetworkAuditURLProtocol.self }.count, 1)
    }

    func testHTTPVersionNames() {
        XCTAssertEqual(NetworkAuditURLProtocol.httpVersion("h2"), "HTTP/2")
        XCTAssertEqual(NetworkAuditURLProtocol.httpVersion("h3"), "HTTP/3")
        XCTAssertEqual(NetworkAuditURLProtocol.httpVersion("http/1.1"), "HTTP/1.1")
    }
}
