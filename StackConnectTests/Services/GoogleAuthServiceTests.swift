import XCTest
@testable import StackConnect

/// `GoogleAuthService` and its building blocks (plan Phase 2): PKCE, the
/// authorization URL, callback parsing, code exchange / refresh / revoke with
/// a mocked token endpoint, scope comparison and `invalid_grant` handling.
@MainActor
final class GoogleAuthServiceTests: XCTestCase {

    private var http: MockGoogleHTTPClient!
    private var keychain: MockKeyStorable!
    private var authenticator: MockGoogleWebAuthenticator!
    private var clock: Date!
    private var sut: GoogleAuthService!

    override func setUp() async throws {
        try await super.setUp()
        http = MockGoogleHTTPClient()
        keychain = MockKeyStorable()
        authenticator = MockGoogleWebAuthenticator()
        clock = Date(timeIntervalSince1970: 1_000_000)
        sut = makeService()
    }

    override func tearDown() async throws {
        sut = nil
        http = nil
        keychain = nil
        authenticator = nil
        try await super.tearDown()
    }

    private func makeService(configuration: GoogleOAuthConfiguration? = GoogleAuthFixtures.configuration) -> GoogleAuthService {
        GoogleAuthService(
            configuration: configuration,
            http: http,
            store: GoogleLoginKeychainStore(keychain: keychain),
            authenticator: authenticator,
            now: { [unowned self] in self.clock }
        )
    }

    private var store: GoogleLoginKeychainStore { GoogleLoginKeychainStore(keychain: keychain) }

    // MARK: - Configuration

    func testConfigurationDerivesTheReversedClientIdRedirect() {
        let configuration = GoogleAuthFixtures.configuration
        XCTAssertEqual(configuration.redirectScheme, "com.googleusercontent.apps.1234-abc")
        XCTAssertEqual(configuration.redirectURI, "com.googleusercontent.apps.1234-abc:/oauth2redirect")
    }

    func testConfigurationRejectsSomethingThatIsNotAnIOSClientId() {
        XCTAssertNil(GoogleOAuthConfiguration(clientId: ""))
        XCTAssertNil(GoogleOAuthConfiguration(clientId: ".apps.googleusercontent.com"))
        XCTAssertNil(GoogleOAuthConfiguration(clientId: "client-secret.json"))
        XCTAssertNotNil(GoogleOAuthConfiguration(clientId: "  1-x.apps.googleusercontent.com \n"))
    }

    func testTheAppBundlesAClientId() {
        // The test host is the app: its Info.plist carries GoogleOAuthClientID.
        XCTAssertNotNil(GoogleOAuthConfiguration.fromBundle(.main))
    }

    // MARK: - PKCE

    func testPKCEChallengeMatchesTheRFC7636Vector() {
        let pkce = GoogleOAuthPKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedVerifiersAreLongEnoughURLSafeAndRandom() {
        let first = GoogleOAuthPKCE.generate()
        let second = GoogleOAuthPKCE.generate()
        XCTAssertEqual(first.verifier.count, 43)
        XCTAssertNil(first.verifier.range(of: "[^A-Za-z0-9_-]", options: .regularExpression))
        XCTAssertNotEqual(first.verifier, second.verifier)
    }

    // MARK: - Authorization URL

    func testAuthorizationURLCarriesPKCEScopesAndState() throws {
        let request = GoogleOAuthAuthorizationRequest.make(scopes: ["openid", GoogleOAuthScope.firebase])
        let items = try queryItems(request.url(configuration: GoogleAuthFixtures.configuration))

        XCTAssertEqual(items["client_id"], GoogleAuthFixtures.clientId)
        XCTAssertEqual(items["redirect_uri"], "com.googleusercontent.apps.1234-abc:/oauth2redirect")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["scope"], "openid https://www.googleapis.com/auth/firebase")
        XCTAssertEqual(items["code_challenge"], request.pkce.challenge)
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["state"], request.state)
        XCTAssertNil(items["include_granted_scopes"])
        XCTAssertNil(items["login_hint"])
    }

    func testIncrementalAuthorizationURLKeepsGrantedScopesAndHintsTheAccount() throws {
        let request = GoogleOAuthAuthorizationRequest.make(scopes: [GoogleOAuthScope.cloudPlatform], includeGrantedScopes: true, loginHint: "dev+tag@example.com")
        let url = request.url(configuration: GoogleAuthFixtures.configuration)
        let items = try queryItems(url)

        XCTAssertEqual(items["include_granted_scopes"], "true")
        XCTAssertEqual(items["login_hint"], "dev+tag@example.com")
        XCTAssertTrue(url.absoluteString.contains("dev%2Btag%40example.com") || url.absoluteString.contains("dev%2Btag@example.com"))
    }

    func testSignInScopesAreTheNonSensitiveSetPlusIdentity() {
        XCTAssertEqual(GoogleOAuthScope.signIn, [
            "openid",
            "https://www.googleapis.com/auth/userinfo.email",
            "https://www.googleapis.com/auth/firebase",
            "https://www.googleapis.com/auth/firebase.messaging",
            "https://www.googleapis.com/auth/androidpublisher",
            "https://www.googleapis.com/auth/playdeveloperreporting"
        ])
        XCTAssertFalse(GoogleOAuthScope.signIn.contains(GoogleOAuthScope.cloudPlatform))
        XCTAssertFalse(GoogleOAuthScope.signIn.contains(GoogleOAuthScope.analyticsReadOnly))
    }

    // MARK: - Callback

    func testCallbackReturnsTheCode() throws {
        let url = try XCTUnwrap(URL(string: "com.googleusercontent.apps.1234-abc:/oauth2redirect?state=s1&code=c1&scope=x"))
        XCTAssertEqual(try GoogleOAuthCallbackParser.authorizationCode(from: url, expectedState: "s1", configuration: GoogleAuthFixtures.configuration), "c1")
    }

    func testCallbackErrorsAreCheckedInOrder() throws {
        let configuration = GoogleAuthFixtures.configuration
        let cases: [(String, GoogleOAuthCallbackError)] = [
            ("https://evil.example/oauth2redirect?state=s1&code=c1", .unexpectedRedirect),
            ("com.googleusercontent.apps.1234-abc:/oauth2redirect?error=access_denied&state=other", .authorizationFailed("access_denied")),
            ("com.googleusercontent.apps.1234-abc:/oauth2redirect?state=other&code=c1", .stateMismatch),
            ("com.googleusercontent.apps.1234-abc:/oauth2redirect?state=s1", .missingCode)
        ]
        for (raw, expected) in cases {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertThrowsError(try GoogleOAuthCallbackParser.authorizationCode(from: url, expectedState: "s1", configuration: configuration), raw) { error in
                XCTAssertEqual(error as? GoogleOAuthCallbackError, expected, raw)
            }
        }
    }

    func testAccessDeniedAndPolicyErrorsMapToAccessDenied() {
        XCTAssertEqual(GoogleAuthError(callbackError: .authorizationFailed("access_denied")), .accessDenied)
        XCTAssertEqual(GoogleAuthError(callbackError: .authorizationFailed("admin_policy_enforced")), .accessDenied)
        XCTAssertEqual(GoogleAuthError(callbackError: .authorizationFailed("server_error")), .callback(.authorizationFailed("server_error")))
        XCTAssertEqual(GoogleAuthError(callbackError: .stateMismatch), .callback(.stateMismatch))
    }

    // MARK: - Token requests

    func testExchangeRequestSendsCodeVerifierAndRedirect() {
        let request = GoogleOAuthTokenClient.exchangeRequest(code: "c/1", verifier: "v", configuration: GoogleAuthFixtures.configuration)
        let fields = MockGoogleHTTPClient.formFields(of: request)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, GoogleOAuthEndpoint.token)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(fields, [
            "client_id": GoogleAuthFixtures.clientId,
            "code": "c/1",
            "code_verifier": "v",
            "grant_type": "authorization_code",
            "redirect_uri": "com.googleusercontent.apps.1234-abc:/oauth2redirect"
        ])
        XCTAssertNil(fields["client_secret"])
    }

    func testRefreshRequestSendsTheRefreshToken() {
        let fields = MockGoogleHTTPClient.formFields(of: GoogleOAuthTokenClient.refreshRequest(refreshToken: "r", configuration: GoogleAuthFixtures.configuration))
        XCTAssertEqual(fields, ["client_id": GoogleAuthFixtures.clientId, "grant_type": "refresh_token", "refresh_token": "r"])
    }

    func testFormEncodingEscapesReservedCharacters() {
        XCTAssertEqual(GoogleOAuthTokenClient.formEncode([("a b", "x/y:z+1=")]), "a%20b=x%2Fy%3Az%2B1%3D")
    }

    // MARK: - Sign-in

    func testSignInExchangesTheCodeAndStoresTheGrant() async throws {
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(refreshToken: "refresh-1"))

        let result = try await sut.signIn(scopes: GoogleOAuthScope.signIn)

        XCTAssertEqual(result.login.loginId, "user-1")
        XCTAssertEqual(result.login.email, "dev@example.com")
        XCTAssertTrue(result.isNewLogin)
        XCTAssertEqual(result.missingScopes, [])
        let exchange = try XCTUnwrap(http.requests(to: "/token").first)
        XCTAssertEqual(MockGoogleHTTPClient.formFields(of: exchange)["code"], "auth-code")
        // The verifier sent is the one whose challenge went to Google.
        let authURL = try XCTUnwrap(authenticator.authorizationURLs.first)
        let challenge = try queryItems(authURL)["code_challenge"]
        let verifier = try XCTUnwrap(MockGoogleHTTPClient.formFields(of: exchange)["code_verifier"])
        XCTAssertEqual(GoogleOAuthPKCE.challenge(for: verifier), challenge)

        let stored = try XCTUnwrap(store.load(loginId: "user-1"))
        XCTAssertEqual(stored.refreshToken, "refresh-1")
        XCTAssertEqual(stored.email, "dev@example.com")
        XCTAssertEqual(Set(stored.grantedScopes), Set(GoogleOAuthScope.signIn))
        XCTAssertEqual(keychain.storedKeys, ["googleLogin.user-1"])
    }

    func testSignInUsesTheCachedAccessTokenWithoutARefresh() async throws {
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(accessToken: "fresh"))
        _ = try await sut.signIn(scopes: GoogleOAuthScope.signIn)

        let token = try await sut.accessToken(forLogin: "user-1")

        XCTAssertEqual(token, "fresh")
        XCTAssertEqual(http.requests(to: "/token").count, 1, "no refresh while the access token is valid")
    }

    func testSignInReportsUntickedScopes() async throws {
        let granted = GoogleOAuthScope.identity + [GoogleOAuthScope.firebase, GoogleOAuthScope.playDeveloperReporting]
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(scopes: granted))

        let result = try await sut.signIn(scopes: GoogleOAuthScope.signIn)

        XCTAssertEqual(result.missingScopes, [GoogleOAuthScope.firebaseMessaging, GoogleOAuthScope.androidPublisher])
        XCTAssertEqual(sut.missingScopes([GoogleOAuthScope.firebase, GoogleOAuthScope.androidPublisher], for: "user-1"), [GoogleOAuthScope.androidPublisher])
        XCTAssertTrue(sut.hasGranted([GoogleOAuthScope.firebase], for: "user-1"))
    }

    func testSigningInAgainReplacesTheGrantOfTheSameLogin() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(refreshToken: "new-refresh"))

        let result = try await sut.signIn(scopes: GoogleOAuthScope.signIn)

        XCTAssertFalse(result.isNewLogin)
        XCTAssertEqual(store.load(loginId: "user-1")?.refreshToken, "new-refresh")
    }

    func testSignInWithoutRefreshTokenForANewLoginFails() async {
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(refreshToken: nil))

        await assertThrows(GoogleAuthError.noRefreshToken) { _ = try await self.sut.signIn(scopes: GoogleOAuthScope.signIn) }
        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    func testSignInWithoutIDTokenFails() async {
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(idToken: nil))

        await assertThrows(GoogleAuthError.missingIdentity) { _ = try await self.sut.signIn(scopes: GoogleOAuthScope.signIn) }
    }

    func testCancelledSheetIsReportedAndNothingIsStored() async {
        authenticator.outcome = .throwing(GoogleAuthError.cancelled)

        await assertThrows(GoogleAuthError.cancelled) { _ = try await self.sut.signIn(scopes: GoogleOAuthScope.signIn) }
        XCTAssertTrue(http.requests.isEmpty)
        XCTAssertTrue(keychain.storedKeys.isEmpty)
    }

    func testAccessDeniedRedirectIsAccessDenied() async {
        authenticator.outcome = .error("access_denied")

        await assertThrows(GoogleAuthError.accessDenied) { _ = try await self.sut.signIn(scopes: GoogleOAuthScope.signIn) }
        XCTAssertTrue(http.requests.isEmpty, "no code exchange after an error redirect")
    }

    func testForgedStateIsRefusedBeforeTheExchange() async {
        authenticator.outcome = .wrongState

        await assertThrows(GoogleAuthError.callback(.stateMismatch)) { _ = try await self.sut.signIn(scopes: GoogleOAuthScope.signIn) }
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testUnconfiguredBuildRefusesToSignIn() async {
        sut = makeService(configuration: nil)

        XCTAssertFalse(sut.isConfigured)
        await assertThrows(GoogleAuthError.notConfigured) { _ = try await self.sut.signIn(scopes: GoogleOAuthScope.signIn) }
    }

    // MARK: - Incremental scopes

    func testIncrementalRequestAsksOnlyForTheNewScopesOnTopOfTheGrant() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(refreshToken: nil, scopes: GoogleOAuthScope.signIn + [GoogleOAuthScope.cloudPlatform]))

        let result = try await sut.requestAdditionalScopes([GoogleOAuthScope.cloudPlatform], for: "user-1")

        let items = try queryItems(XCTUnwrap(authenticator.authorizationURLs.first))
        XCTAssertEqual(items["include_granted_scopes"], "true")
        XCTAssertEqual(items["login_hint"], "dev@example.com")
        XCTAssertEqual(items["scope"], (GoogleOAuthScope.identity + [GoogleOAuthScope.cloudPlatform]).joined(separator: " "))
        XCTAssertEqual(result.missingScopes, [])
        XCTAssertFalse(result.isNewLogin)
        let stored = try XCTUnwrap(store.load(loginId: "user-1"))
        XCTAssertEqual(stored.refreshToken, "stored-refresh", "kept when the exchange returns none")
        XCTAssertTrue(stored.grantedScopeSet.contains(GoogleOAuthScope.cloudPlatform))
    }

    func testIncrementalRequestForAnUnknownLoginFails() async {
        await assertThrows(GoogleAuthError.loginNotFound) {
            _ = try await self.sut.requestAdditionalScopes([GoogleOAuthScope.cloudPlatform], for: "nobody")
        }
    }

    func testIncrementalRequestRefusesAnotherGoogleAccount() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(idToken: GoogleAuthFixtures.idToken(sub: "someone-else")))

        await assertThrows(GoogleAuthError.differentAccount(expectedEmail: "dev@example.com")) {
            _ = try await self.sut.requestAdditionalScopes([GoogleOAuthScope.cloudPlatform], for: "user-1")
        }
        XCTAssertEqual(store.load(loginId: "user-1")?.refreshToken, "stored-refresh")
        XCTAssertNil(store.load(loginId: "someone-else"))
    }

    // MARK: - Sign in again

    func testReauthenticateHintsTheLoginAndReplacesOnlyItsRefreshToken() async throws {
        store.save(GoogleAuthFixtures.grant(scopes: GoogleOAuthScope.signIn + [GoogleOAuthScope.cloudPlatform]))
        store.save(GoogleAuthFixtures.grant(loginId: "user-2", email: "other@example.com"))
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(
            refreshToken: "new-refresh",
            scopes: GoogleOAuthScope.signIn + [GoogleOAuthScope.cloudPlatform]
        ))

        let result = try await sut.reauthenticate(loginId: "user-1")

        let items = try queryItems(XCTUnwrap(authenticator.authorizationURLs.first))
        XCTAssertEqual(items["login_hint"], "dev@example.com")
        let requested = Set(items["scope"]?.split(separator: " ").map(String.init) ?? [])
        XCTAssertTrue(requested.isSuperset(of: GoogleOAuthScope.signIn), "at least the sign-in scopes")
        XCTAssertTrue(requested.contains(GoogleOAuthScope.cloudPlatform), "scopes granted before are asked again")
        XCTAssertEqual(result.login.loginId, "user-1")
        XCTAssertFalse(result.isNewLogin)
        XCTAssertEqual(store.load(loginId: "user-1")?.refreshToken, "new-refresh")
        XCTAssertEqual(store.load(loginId: "user-2")?.refreshToken, "stored-refresh", "other logins untouched")
    }

    func testReauthenticateRefusesAnotherGoogleAccount() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(
            refreshToken: "intruder-refresh",
            idToken: GoogleAuthFixtures.idToken(sub: "someone-else", email: "else@example.com")
        ))

        await assertThrows(GoogleAuthError.differentAccount(expectedEmail: "dev@example.com")) {
            _ = try await self.sut.reauthenticate(loginId: "user-1")
        }
        XCTAssertEqual(store.load(loginId: "user-1")?.refreshToken, "stored-refresh", "never re-bound")
        XCTAssertNil(store.load(loginId: "someone-else"), "the other account's grant is not kept")
    }

    func testReauthenticateRestoresALoginWhoseGrantIsMissing() async throws {
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(refreshToken: "new-refresh"))

        let result = try await sut.reauthenticate(loginId: "user-1")

        XCTAssertEqual(result.login.loginId, "user-1")
        XCTAssertEqual(store.load(loginId: "user-1")?.refreshToken, "new-refresh")
    }

    // MARK: - Invalidation

    func testInvalidatedAccessTokenIsRefreshedOnTheNextRequest() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(accessToken: "first", refreshToken: nil, scopes: nil, idToken: nil), once: true)
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(accessToken: "second", refreshToken: nil, scopes: nil, idToken: nil))

        let first = try await sut.accessToken(forLogin: "user-1")
        let cached = try await sut.accessToken(forLogin: "user-1")
        sut.invalidateAccessToken(forLogin: "user-1")
        let refreshed = try await sut.accessToken(forLogin: "user-1")

        XCTAssertEqual(first, "first")
        XCTAssertEqual(cached, "first", "valid tokens are cached")
        XCTAssertEqual(refreshed, "second")
        XCTAssertEqual(http.requests(to: "/token").count, 2)
        XCTAssertEqual(store.load(loginId: "user-1")?.refreshToken, "stored-refresh", "the refresh token is kept")
    }

    func testInvalidatingOneLoginKeepsTheOthersCached() async throws {
        store.save(GoogleAuthFixtures.grant())
        store.save(GoogleAuthFixtures.grant(loginId: "user-2"))
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(refreshToken: nil, scopes: nil, idToken: nil))
        _ = try await sut.accessToken(forLogin: "user-1")
        _ = try await sut.accessToken(forLogin: "user-2")

        sut.invalidateAccessToken(forLogin: "user-1")
        _ = try await sut.accessToken(forLogin: "user-2")

        XCTAssertEqual(http.requests(to: "/token").count, 2, "user-2 still served from the cache")
    }

    // MARK: - Refresh

    func testAccessTokenRefreshesWithTheStoredRefreshTokenAndKeepsIt() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(accessToken: "refreshed", refreshToken: nil, scopes: nil, idToken: nil))

        let token = try await sut.accessToken(forLogin: "user-1")

        XCTAssertEqual(token, "refreshed")
        let refresh = try XCTUnwrap(http.requests(to: "/token").first)
        XCTAssertEqual(MockGoogleHTTPClient.formFields(of: refresh)["refresh_token"], "stored-refresh")
        let stored = try XCTUnwrap(store.load(loginId: "user-1"))
        XCTAssertEqual(stored.refreshToken, "stored-refresh")
        XCTAssertEqual(Set(stored.grantedScopes), Set(GoogleOAuthScope.signIn), "scopes kept when the response has none")
    }

    func testAccessTokenIsRefreshedAgainOnlyNearExpiry() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(accessToken: "a", expiresIn: 3600, refreshToken: nil, idToken: nil))

        _ = try await sut.accessToken(forLogin: "user-1")
        clock = clock.addingTimeInterval(3600 - GoogleAuthService.expiryLeeway - 1)
        _ = try await sut.accessToken(forLogin: "user-1")
        XCTAssertEqual(http.requests(to: "/token").count, 1)

        clock = clock.addingTimeInterval(2)
        _ = try await sut.accessToken(forLogin: "user-1")
        XCTAssertEqual(http.requests(to: "/token").count, 2)
    }

    func testConcurrentCallersShareOneRefresh() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(accessToken: "shared", refreshToken: nil, idToken: nil))

        let service: GoogleAuthService = sut
        async let first = service.accessToken(forLogin: "user-1")
        async let second = service.accessToken(forLogin: "user-1")
        let tokens = try await [first, second]

        XCTAssertEqual(tokens, ["shared", "shared"])
        XCTAssertEqual(http.requests(to: "/token").count, 1)
    }

    func testInvalidGrantAsksThatLoginToSignInAgain() async {
        store.save(GoogleAuthFixtures.grant(email: "dev@example.com"))
        http.respond(to: "/token", status: 400, json: ["error": "invalid_grant", "error_description": "Token has been expired or revoked."])

        await assertThrows(GoogleAuthError.signInExpired(email: "dev@example.com")) {
            _ = try await self.sut.accessToken(forLogin: "user-1")
        }
        XCTAssertTrue(GoogleAuthError.signInExpired(email: nil).requiresSignIn)
        XCTAssertNotNil(store.load(loginId: "user-1"), "kept, so signing in again with the same Google user restores its accounts")
    }

    func testInvalidGrantOfOneLoginLeavesTheOthersWorking() async throws {
        store.save(GoogleAuthFixtures.grant(loginId: "user-1"))
        var other = GoogleAuthFixtures.grant(loginId: "user-2")
        other.refreshToken = "other-refresh"
        store.save(other)
        http.respond(to: "/token", json: GoogleAuthFixtures.tokenResponse(accessToken: "ok", refreshToken: nil, idToken: nil))
        // `stored-refresh` (user-1) is rejected, `other-refresh` (user-2) works.
        let rejecting = MockGoogleHTTPClient()
        rejecting.respond(to: "/token", status: 400, json: ["error": "invalid_grant"])
        let service = GoogleAuthService(
            configuration: GoogleAuthFixtures.configuration,
            http: RoutingByRefreshToken(routes: ["stored-refresh": rejecting, "other-refresh": http]),
            store: store,
            authenticator: authenticator,
            now: { [unowned self] in self.clock }
        )

        await assertThrows(GoogleAuthError.signInExpired(email: "dev@example.com")) {
            _ = try await service.accessToken(forLogin: "user-1")
        }
        let token = try await service.accessToken(forLogin: "user-2")
        XCTAssertEqual(token, "ok")
    }

    func testUnknownLoginHasNoAccessToken() async {
        await assertThrows(GoogleAuthError.loginNotFound) { _ = try await self.sut.accessToken(forLogin: "nobody") }
        XCTAssertEqual(sut.missingScopes([GoogleOAuthScope.firebase], for: "nobody"), [GoogleOAuthScope.firebase])
    }

    func testOfflineRefreshIsANetworkError() async {
        store.save(GoogleAuthFixtures.grant())
        http.error = URLError(.notConnectedToInternet)

        await assertThrows(GoogleAuthError.network(.notConnectedToInternet)) { _ = try await self.sut.accessToken(forLogin: "user-1") }
    }

    // MARK: - Sign-out / revoke

    func testSignOutRevokesTheRefreshTokenAndDeletesTheGrant() async throws {
        store.save(GoogleAuthFixtures.grant())
        http.respond(to: "/revoke", json: [String: Any]())

        await sut.signOut(loginId: "user-1")

        let revoke = try XCTUnwrap(http.requests(to: "/revoke").first)
        XCTAssertEqual(revoke.url, GoogleOAuthEndpoint.revoke)
        XCTAssertEqual(MockGoogleHTTPClient.formFields(of: revoke), ["token": "stored-refresh"])
        XCTAssertNil(store.load(loginId: "user-1"))
        XCTAssertNil(sut.login(id: "user-1"))
    }

    func testSignOutDeletesTheGrantEvenWhenTheRevokeFails() async {
        store.save(GoogleAuthFixtures.grant())
        http.error = URLError(.notConnectedToInternet)

        await sut.signOut(loginId: "user-1")

        XCTAssertNil(store.load(loginId: "user-1"))
    }

    func testRevokeTreatsAnAlreadyRevokedTokenAsDone() async throws {
        http.respond(to: "/revoke", status: 400, json: ["error": "invalid_token"])
        let client = GoogleOAuthTokenClient(configuration: GoogleAuthFixtures.configuration, http: http)

        try await client.revoke(token: "t")
    }

    // MARK: - Scopes, ID token, errors

    func testScopeParsingAndComparison() {
        XCTAssertEqual(GoogleOAuthScope.parse("a  b\nc"), ["a", "b", "c"])
        XCTAssertEqual(GoogleOAuthScope.parse(nil), [])
        // Identity scopes have no checkbox: never reported missing.
        XCTAssertEqual(GoogleOAuthScope.missing(GoogleOAuthScope.signIn, in: [GoogleOAuthScope.firebase]), [
            GoogleOAuthScope.firebaseMessaging, GoogleOAuthScope.androidPublisher, GoogleOAuthScope.playDeveloperReporting
        ])
    }

    func testFeaturesTurnedOffByMissingScopes() {
        XCTAssertEqual(GoogleScopeFeature.disabled(by: [GoogleOAuthScope.firebaseMessaging, GoogleOAuthScope.androidPublisher], for: .firebase), [.cloudMessaging])
        XCTAssertEqual(GoogleScopeFeature.disabled(by: [GoogleOAuthScope.firebaseMessaging, GoogleOAuthScope.androidPublisher], for: .googlePlay), [.playContent])
        XCTAssertEqual(GoogleScopeFeature.requiredScopes(for: .firebase), [GoogleOAuthScope.firebase])
        XCTAssertEqual(GoogleScopeFeature.requiredScopes(for: .googlePlay), [GoogleOAuthScope.playDeveloperReporting])
        XCTAssertTrue(GoogleScopeFeature.features(for: .apple).isEmpty)
    }

    func testIDTokenClaims() throws {
        let claims = try XCTUnwrap(GoogleIDTokenClaims(idToken: GoogleAuthFixtures.idToken(sub: "123", email: "a@b.c")))
        XCTAssertEqual(claims.subject, "123")
        XCTAssertEqual(claims.email, "a@b.c")
        XCTAssertNil(GoogleIDTokenClaims(idToken: "not-a-jwt"))
        XCTAssertNil(GoogleIDTokenClaims(idToken: GoogleAuthFixtures.idToken(sub: "")))
    }

    func testGoogleErrorBodiesAreClassifiedByStatusAndReason() throws {
        let disabled = try XCTUnwrap(GoogleAPIErrorSummary.parse(json([
            "error": ["code": 403, "status": "PERMISSION_DENIED", "message": "Firebase Management API has not been used in project 1",
                      "details": [["@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "SERVICE_DISABLED"]]]
        ])))
        XCTAssertTrue(disabled.isServiceDisabled)
        XCTAssertEqual(disabled.logLine, "status=PERMISSION_DENIED reasons=SERVICE_DISABLED")
        XCTAssertFalse(disabled.logLine.contains("Firebase Management"), "the free-text message is never logged")

        let quota = try XCTUnwrap(GoogleAPIErrorSummary.parse(json(["error": ["code": 429, "status": "RESOURCE_EXHAUSTED"]])))
        XCTAssertTrue(quota.isQuotaExceeded)

        let scope = try XCTUnwrap(GoogleAPIErrorSummary.parse(json([
            "error": ["code": 403, "status": "PERMISSION_DENIED", "details": [["reason": "ACCESS_TOKEN_SCOPE_INSUFFICIENT"]]]
        ])))
        XCTAssertTrue(scope.isScopeInsufficient)

        XCTAssertEqual(GoogleAPIErrorSummary.parse(json(["error": "invalid_grant"]))?.oauthError, "invalid_grant")
        XCTAssertNil(GoogleAPIErrorSummary.parse(Data("nope".utf8)))
    }

    func testErrorCategories() {
        let disabled = GoogleAuthError.http(statusCode: 403, summary: GoogleAPIErrorSummary(status: "PERMISSION_DENIED", reasons: ["SERVICE_DISABLED"]))
        let quota = GoogleAuthError.http(statusCode: 429, summary: nil)
        let scope = GoogleAuthError.http(statusCode: 403, summary: GoogleAPIErrorSummary(reasons: ["ACCESS_TOKEN_SCOPE_INSUFFICIENT"]))
        let cases: [(GoogleAuthError, AnalyticsErrorCategory)] = [
            (.accessDenied, .forbidden),
            (.invalidGrant, .invalidCredentials),
            (.signInExpired(email: nil), .invalidCredentials),
            (.loginNotFound, .invalidCredentials),
            (.network(.timedOut), .network),
            (.missingIdentity, .server),
            (disabled, .server),
            (quota, .unknown),
            (scope, .scopeDenied),
            (.http(statusCode: 403, summary: nil), .forbidden),
            (.http(statusCode: 503, summary: nil), .server),
            (.callback(.stateMismatch), .unknown)
        ]
        for (error, category) in cases {
            XCTAssertEqual(AnalyticsErrorCategory(connectionError: error), category, "\(error)")
        }
        // A Play sign-in failure the core hands back is mapped to its
        // `GoogleAuthError` first, so it lands in the same category.
        let playSignIn = GoogleSignInCoreTokenProvider(loginId: "user-1", tokens: StaticGoogleAccessTokenProvider())
            .signInError(for: GoogleSignInCoreAuthMarker.authError(.invalidGrant, detail: "expired"))
        XCTAssertEqual(AnalyticsErrorCategory(connectionError: playSignIn ?? GoogleAuthError.cancelled), .invalidCredentials)
    }

    func testServiceDisabledAndQuotaShowTheGenericMessage() {
        let generic = String(localized: "Google couldn't complete the request right now. Try again later.")
        XCTAssertEqual(GoogleAuthError.http(statusCode: 403, summary: GoogleAPIErrorSummary(reasons: ["SERVICE_DISABLED"])).errorDescription, generic)
        XCTAssertEqual(GoogleAuthError.http(statusCode: 429, summary: nil).errorDescription, generic)
        XCTAssertEqual(GoogleAuthError.http(statusCode: 500, summary: nil).errorDescription, generic)
    }

    // MARK: - Helpers

    private func queryItems(_ url: URL) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        var items: [String: String] = [:]
        for item in components.queryItems ?? [] { items[item.name] = item.value }
        return items
    }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func assertThrows(
        _ expected: GoogleAuthError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GoogleAuthError, expected, file: file, line: line)
        }
    }
}

/// Routes token-endpoint requests by the refresh token they carry.
private struct RoutingByRefreshToken: GoogleHTTPClient {
    let routes: [String: MockGoogleHTTPClient]

    func send(_ request: URLRequest) async throws -> GoogleHTTPResponse {
        let token = MockGoogleHTTPClient.formFields(of: request)["refresh_token"] ?? ""
        guard let client = routes[token] else { return GoogleHTTPResponse(statusCode: 404, data: Data()) }
        return try await client.send(request)
    }
}
