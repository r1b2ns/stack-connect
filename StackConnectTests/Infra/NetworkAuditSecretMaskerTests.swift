import XCTest
@testable import StackConnect

final class NetworkAuditSecretMaskerTests: XCTestCase {

    private typealias Masker = NetworkAuditSecretMasker

    // MARK: - Header classification

    func testSecretHeadersAreClassified() {
        for name in ["Authorization", "authorization", "Proxy-Authorization", "Cookie", "Set-Cookie",
                     "X-Goog-Api-Key", "X-API-Key", "scnt", "X-Apple-ID-Session-Id",
                     "X-Goog-Firebase-Installations-Auth", "X-Refresh-Token", "Client-Secret"] {
            XCTAssertTrue(Masker.isSecretHeader(name), name)
        }
        for name in ["Accept", "Content-Type", "User-Agent", "x-request-id", "Content-Encoding", "x-rate-limit"] {
            XCTAssertFalse(Masker.isSecretHeader(name), name)
        }
    }

    func testBearerHeaderIsMaskedWithShortPreview() {
        let header = Masker.maskHeader(name: "Authorization", value: "Bearer eyJhbGciOiJFUzI1NiJ9.payload.sig")

        XCTAssertTrue(header.isSecret)
        XCTAssertEqual(header.value, "Bearer [MASKED]")
        XCTAssertEqual(header.maskedPreview, "Bearer eyJhbG••••••••")
    }

    func testBasicAndUnknownSchemesAreMasked() {
        XCTAssertEqual(Masker.maskHeader(name: "Authorization", value: "Basic dXNlcjpwYXNz").value, "Basic [MASKED]")
        XCTAssertEqual(Masker.maskHeader(name: "X-Goog-Api-Key", value: "AIzaSyD-123").value, "[MASKED]")
    }

    func testCookieKeepsNamesOnly() {
        let header = Masker.maskHeader(name: "Cookie", value: "myacinfo=SECRET1; dqsid=SECRET2")

        XCTAssertEqual(header.value, "myacinfo=[MASKED]; dqsid=[MASKED]")
        XCTAssertFalse(header.value.contains("SECRET"))
        XCTAssertFalse(header.maskedPreview?.contains("SECRET") ?? true)
    }

    func testSetCookieKeepsAttributes() {
        let header = Masker.maskHeader(name: "Set-Cookie", value: "myacinfo=SECRET; Path=/; Secure; HttpOnly")

        XCTAssertEqual(header.value, "myacinfo=[MASKED]; Path=/; Secure; HttpOnly")
    }

    func testPlainHeaderIsKept() {
        let header = Masker.maskHeader(name: "Accept", value: "application/json")

        XCTAssertFalse(header.isSecret)
        XCTAssertEqual(header.value, "application/json")
        XCTAssertNil(header.maskedPreview)
    }

    // MARK: - URLs

    func testSecretQueryParametersAreMasked() {
        let url = URL(string: "https://firebase.googleapis.com/v1/projects?key=AIzaSECRET&pageSize=100&access_token=ya29.SECRET")!

        let masked = Masker.maskURL(url)

        XCTAssertEqual(masked, "https://firebase.googleapis.com/v1/projects?key=[MASKED]&pageSize=100&access_token=[MASKED]")
        XCTAssertEqual(Masker.maskedPathAndQuery(url), "/v1/projects?key=[MASKED]&pageSize=100&access_token=[MASKED]")
    }

    func testURLWithoutQueryIsUnchanged() {
        let url = URL(string: "https://api.appstoreconnect.apple.com/v1/apps")!

        XCTAssertEqual(Masker.maskURL(url), "https://api.appstoreconnect.apple.com/v1/apps")
        XCTAssertEqual(Masker.maskedPathAndQuery(url), "/v1/apps")
    }

    func testEmbeddedPasswordIsMasked() {
        let url = URL(string: "https://user:hunter2@example.com/path")!

        XCTAssertFalse(Masker.maskURL(url).contains("hunter2"))
    }

    func testParameterClassification() {
        for name in ["key", "api_key", "access_token", "accessToken", "refresh_token", "id_token", "client_secret",
                     "assertion", "client_assertion", "code", "X-Goog-Signature", "password", "subject_token"] {
            XCTAssertTrue(Masker.isSecretParameter(name), name)
        }
        for name in ["limit", "include", "grant_type", "pageSize", "sort", "filter[platform]"] {
            XCTAssertFalse(Masker.isSecretParameter(name), name)
        }
    }

    // MARK: - Bodies

    func testJSONBodySecretsAreMaskedAtAnyDepth() throws {
        let body = Data("""
        {"type":"service_account","private_key":"-----BEGIN PRIVATE KEY-----\\nMIIEv\\n-----END PRIVATE KEY-----\\n",
         "client_email":"bot@project.iam.gserviceaccount.com","client_secret":"S3CR3T",
         "nested":{"refresh_token":"1//0gREFRESH","items":[{"id_token":"ID","assertion":"A"}]},
         "key":"welcome_message","code":409}
        """.utf8)

        let masked = try XCTUnwrap(Masker.maskBody(body, contentType: "application/json"))

        for secret in ["BEGIN PRIVATE KEY", "S3CR3T", "1//0gREFRESH", "\"ID\"", "\"A\""] {
            XCTAssertFalse(masked.contains(secret), secret)
        }
        XCTAssertTrue(masked.contains("\"client_email\" : \"bot@project.iam.gserviceaccount.com\""))
        // A bare `key` / `code` in JSON is data (Remote Config keys, error codes).
        XCTAssertTrue(masked.contains("\"key\" : \"welcome_message\""))
        XCTAssertTrue(masked.contains("\"code\" : 409"))
    }

    func testFormEncodedBodySecretsAreMasked() throws {
        let body = Data("grant_type=refresh_token&refresh_token=1%2F%2F0gABCDEF&client_id=123.apps.googleusercontent.com".utf8)

        let masked = try XCTUnwrap(Masker.maskBody(body, contentType: "application/x-www-form-urlencoded"))

        XCTAssertEqual(masked, "grant_type=refresh_token&refresh_token=[MASKED]&client_id=123.apps.googleusercontent.com")
    }

    func testJWTAssertionInFormBodyIsMasked() throws {
        let jwt = NetworkAuditFixtures.jwt(["iss": "bot@project.iam.gserviceaccount.com", "aud": "https://oauth2.googleapis.com/token"])
        let body = Data("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(jwt)".utf8)

        let masked = try XCTUnwrap(Masker.maskBody(body, contentType: nil))

        XCTAssertFalse(masked.contains(jwt))
        XCTAssertTrue(masked.hasSuffix("assertion=[MASKED]"))
    }

    func testFreeTextSecretsAreMasked() {
        let p8 = "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg\n-----END PRIVATE KEY-----"
        let jwt = NetworkAuditFixtures.jwt(["aud": "appstoreconnect-v1"])
        let text = "key: \(p8)\ntoken \(jwt)\naccess ya29.a0AfB_byC1234567890abcdef\nrefresh 1//0gABCDEFGHIJKLMNOPQRSTUV\napi AIzaSyD1234567890abcdefghijklmnopqrstuv"

        let masked = Masker.maskFreeText(text)

        XCTAssertFalse(masked.contains("BEGIN PRIVATE KEY"))
        XCTAssertFalse(masked.contains(jwt))
        XCTAssertFalse(masked.contains("ya29."))
        XCTAssertFalse(masked.contains("1//0g"))
        XCTAssertFalse(masked.contains("AIzaSy"))
        XCTAssertEqual(masked.components(separatedBy: "[MASKED]").count - 1, 5)
    }

    func testBinaryBodyIsNotRendered() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x1A, 0x0A])

        XCTAssertNil(Masker.maskBody(png, contentType: "image/png"))
    }

    func testPlainTextBodyIsKept() {
        XCTAssertEqual(Masker.maskBody(Data("hello world".utf8), contentType: "text/plain"), "hello world")
    }

    // MARK: - Credentials

    func testAppStoreConnectJWTIsShortLivedWithExpiry() {
        let expiry = NetworkAuditFixtures.now.addingTimeInterval(12 * 60)
        let info = Masker.credentialInfo(forAuthorization: "Bearer \(NetworkAuditFixtures.ascJWT(expiresAt: expiry))")

        XCTAssertEqual(info.kind, .appStoreConnectJWT)
        XCTAssertEqual(info.expiresAt?.timeIntervalSince1970, expiry.timeIntervalSince1970.rounded(.down))
        XCTAssertTrue(info.isShortLived)
    }

    func testOtherJWTIsAlwaysMasked() {
        let jwt = NetworkAuditFixtures.jwt(["aud": "https://oauth2.googleapis.com/token", "exp": 1_900_000_000])

        XCTAssertEqual(Masker.credentialInfo(forAuthorization: "Bearer \(jwt)").kind, .other)
    }

    func testGoogleAccessTokenUsesTheRegistryExpiry() {
        let expiry = NetworkAuditFixtures.now.addingTimeInterval(3_600)
        let info = Masker.credentialInfo(forAuthorization: "Bearer ya29.a0AfB_token") { token in
            token == "ya29.a0AfB_token" ? expiry : nil
        }

        XCTAssertEqual(info.kind, .googleAccessToken)
        XCTAssertEqual(info.expiresAt, expiry)
    }

    func testBasicAuthIsOther() {
        XCTAssertEqual(Masker.credentialInfo(forAuthorization: "Basic dXNlcjpwYXNz").kind, .other)
    }

    // MARK: - Token inclusion

    func testTokenInclusionRules() {
        let now = NetworkAuditFixtures.now
        let valid = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(
            authorization: "Bearer \(NetworkAuditFixtures.ascJWT(expiresAt: now.addingTimeInterval(600)))"
        ))
        let expired = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(
            authorization: "Bearer \(NetworkAuditFixtures.ascJWT(expiresAt: now.addingTimeInterval(-60)))"
        ))
        let unknownGoogle = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(
            url: "https://firebase.googleapis.com/v1beta1/projects",
            authorization: "Bearer ya29.unknown_expiry_token"
        ))
        let basic = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(authorization: "Basic dXNlcjpwYXNz"))
        let none = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange())

        XCTAssertTrue(NetworkAuditTokenInclusion.evaluate(valid, now: now).canInclude)
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(expired, now: now), .expired(.appStoreConnectJWT, at: expired.credential!.expiresAt!))
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(unknownGoogle, now: now), .unknownValidity(.googleAccessToken))
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(basic, now: now), .alwaysMasked)
        XCTAssertEqual(NetworkAuditTokenInclusion.evaluate(none, now: now), .notApplicable)
    }

    // MARK: - Host catalog

    func testHostCatalogCategories() {
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "api.appstoreconnect.apple.com").category, .apple)
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "androidpublisher.googleapis.com").category, .google)
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "app-measurement.com").category, .telemetry)
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "is1-ssl.mzstatic.com").category, .apple)
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "example.org").category, .other)
        // The app's own Remote Config fetch is telemetry; a user's project is Google.
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "firebaseremoteconfig.googleapis.com",
                                                     path: "/v1/projects/stackconnect/namespaces/firebase:fetch").category, .telemetry)
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "firebaseremoteconfig.googleapis.com",
                                                     path: "/v1/projects/my-app/remoteConfig").category, .google)
    }

    func testFirebaseTelemetryHostsAreTelemetry() {
        let hosts = [
            "app-analytics-services.com", "region1.app-analytics-services.com",
            "app-measurement.com", "region1.app-measurement.com",
            "firebaselogging-pa.googleapis.com", "firebaseinstallations.googleapis.com",
            "crashlyticsreports-pa.googleapis.com", "firebase-settings.crashlytics.com",
            "firebaseremoteconfigrealtime.googleapis.com"
        ]
        for host in hosts {
            let entry = NetworkAuditHostCatalog.entry(host: host)
            XCTAssertEqual(entry.category, .telemetry, host)
            XCTAssertFalse(entry.purpose.isEmpty, host)
            XCTAssertNotEqual(entry.purpose, NetworkAuditHostCatalog.entry(host: "example.org").purpose, host)
        }
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "firebaseremoteconfig.googleapis.com",
                                                     path: "/v1/projects/p/namespaces/firebase:fetch").category, .telemetry)
        XCTAssertEqual(NetworkAuditHostCatalog.entry(host: "not-app-measurement.com").category, .other)
    }

    func testStoredOtherEventsGetTheCurrentCategory() {
        let stored = NetworkAuditEventSummary(
            id: UUID(), kind: .http, direction: .outbound, category: .other, date: Date(), method: "POST",
            host: "app-analytics-services.com", path: "/sdk-exp", statusCode: 200, statusText: nil,
            isSuccess: true, bytesSent: 1, bytesReceived: 1
        )
        let unknown = NetworkAuditEventSummary(
            id: UUID(), kind: .http, direction: .outbound, category: .other, date: Date(), method: "GET",
            host: "example.org", path: "/", statusCode: 200, statusText: nil,
            isSuccess: true, bytesSent: 1, bytesReceived: 1
        )

        XCTAssertEqual(stored.withCurrentCategory().category, .telemetry)
        XCTAssertEqual(unknown.withCurrentCategory().category, .other)
    }
}
