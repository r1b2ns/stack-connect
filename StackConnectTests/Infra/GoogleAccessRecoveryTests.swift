import XCTest
import APIProviderFirebase
@testable import StackConnect

/// `GoogleAccessRecovery`: when a Firebase screen of a "Sign in with Google"
/// account asks for an extra permission or a new sign-in (plan G3, R5), and
/// what "Grant access" / "Sign in again" do for each outcome.
@MainActor
final class GoogleAccessRecoveryTests: XCTestCase {

    private typealias Fixtures = GoogleSignInFirebaseFixtures

    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private let account = GoogleSignInFirebaseFixtures.account()

    override func setUp() async throws {
        try await super.setUp()
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        Fixtures.storeCredentials(for: account, in: keychain)
    }

    private func makeSUT(auth: MockGoogleAuthService, account: AccountModel? = nil) -> GoogleAccessRecovery {
        GoogleAccessRecovery(account: account ?? self.account, keychain: keychain, auth: auth, analytics: analytics, screen: .remoteConfig)
    }

    // MARK: - When to prompt

    func testAsksBeforeLoadingWhenTheScopeIsNotGranted() {
        let sut = makeSUT(auth: Fixtures.auth())

        let prompt = sut.promptBeforeLoading(.remoteConfig)

        XCTAssertEqual(prompt, GoogleAccessPrompt(reason: .permissionNeeded(.remoteConfig), email: Fixtures.email))
    }

    func testDoesNotAskWhenTheScopeIsGranted() {
        let sut = makeSUT(auth: Fixtures.auth(extraScopes: [GoogleOAuthScope.analyticsReadOnly]))

        XCTAssertNil(sut.promptBeforeLoading(.analytics))
        XCTAssertNotNil(sut.promptBeforeLoading(.remoteConfig), "each screen checks its own scope")
    }

    func testServiceAccountsAreNeverPrompted() {
        let serviceAccount = AccountModel(id: "sa", name: "SA", providerType: .firebase)
        keychain.setObject(FirebaseCredentials(serviceAccountJSON: "{}"), forKey: "credentials.sa")
        let sut = makeSUT(auth: Fixtures.auth(), account: serviceAccount)

        XCTAssertNil(sut.loginId)
        XCTAssertNil(sut.promptBeforeLoading(.remoteConfig))
        XCTAssertNil(sut.prompt(for: GoogleAuthError.signInExpired(email: nil)))
        XCTAssertNil(sut.prompt(for: Self.scopeInsufficient, feature: .remoteConfig))
    }

    func testFeatureScopesComeFromTheScopeConstants() {
        XCTAssertEqual(GoogleSensitiveScopeFeature.remoteConfig.scope, GoogleOAuthScope.cloudPlatform)
        XCTAssertEqual(GoogleSensitiveScopeFeature.analytics.scope, GoogleOAuthScope.analyticsReadOnly)
    }

    // MARK: - Errors → prompt

    func testAnExpiredSignInAsksToSignInAgain() {
        let sut = makeSUT(auth: Fixtures.auth())

        for error: GoogleAuthError in [.invalidGrant, .signInExpired(email: Fixtures.email), .loginNotFound] {
            XCTAssertEqual(sut.prompt(for: error)?.reason, .signInRequired, "\(error)")
        }
    }

    func testAScopeRevokedElsewhereFallsBackToTheExplanation() {
        let sut = makeSUT(auth: Fixtures.auth(extraScopes: [GoogleOAuthScope.cloudPlatform]))

        XCTAssertEqual(sut.prompt(for: Self.scopeInsufficient, feature: .remoteConfig)?.reason, .permissionNeeded(.remoteConfig))
        XCTAssertNil(sut.prompt(for: Self.scopeInsufficient), "no screen feature, no permission prompt")
    }

    func testOtherErrorsAreNotPrompts() {
        let sut = makeSUT(auth: Fixtures.auth())
        let forbidden = APIProviderFirebase.Error.requestFailure(403, nil, nil)

        XCTAssertNil(sut.prompt(for: forbidden, feature: .remoteConfig))
        XCTAssertNil(sut.prompt(for: GoogleAuthError.network(.notConnectedToInternet), feature: .remoteConfig))
    }

    // MARK: - Grant access

    func testGrantingAsksForTheScopeOfTheLoginAndResolves() async {
        let auth = Fixtures.auth()
        auth.additionalScopesResult = .success(Fixtures.result(scopes: GoogleOAuthScope.signIn + [GoogleOAuthScope.cloudPlatform]))
        let sut = makeSUT(auth: auth)
        var states: [GoogleAccessPrompt] = []

        let resolved = await sut.resolve(prompt(.permissionNeeded(.remoteConfig))) { states.append($0) }

        XCTAssertTrue(resolved)
        XCTAssertEqual(auth.additionalScopesCalls.map(\.scopes), [[GoogleOAuthScope.cloudPlatform]])
        XCTAssertEqual(auth.additionalScopesCalls.map(\.loginId), [Fixtures.loginId])
        XCTAssertEqual(states.map(\.isWorking), [true])
        XCTAssertEqual(analytics.taps(of: .grantGoogleAccess).count, 1)
        XCTAssertEqual(analytics.actions(of: .googleScopeGrantStarted).first?.parameters[AnalyticsParameterKey.kind], .string("remote_config"))
        XCTAssertEqual(analytics.results(of: .googleScopeGrant), [.success])
    }

    func testCancellingStaysOnTheExplanationWithoutAnError() async {
        let auth = Fixtures.auth()
        auth.additionalScopesResult = .failure(GoogleAuthError.cancelled)
        let sut = makeSUT(auth: auth)
        var last: GoogleAccessPrompt?

        let resolved = await sut.resolve(prompt(.permissionNeeded(.analytics))) { last = $0 }

        XCTAssertFalse(resolved)
        XCTAssertEqual(last?.reason, .permissionNeeded(.analytics))
        XCTAssertNil(last?.feedback)
        XCTAssertEqual(last?.isWorking, false)
        XCTAssertEqual(analytics.results(of: .googleScopeGrant), [.cancelled])
    }

    func testAnUntickedCheckboxExplainsAndAllowsARetry() async {
        let auth = Fixtures.auth()
        auth.additionalScopesResult = .success(Fixtures.result(scopes: GoogleOAuthScope.signIn))
        let sut = makeSUT(auth: auth)
        var last: GoogleAccessPrompt?

        let resolved = await sut.resolve(prompt(.permissionNeeded(.remoteConfig))) { last = $0 }

        XCTAssertFalse(resolved)
        XCTAssertEqual(last?.reason, .permissionNeeded(.remoteConfig))
        XCTAssertNotNil(last?.feedback)
        XCTAssertEqual(last?.isWorking, false, "Grant Access can be tapped again")
        XCTAssertEqual(analytics.results(of: .googleScopeGrant), [.failure])
        XCTAssertEqual(analytics.actions(of: .googleScopeGrant).first?.parameters[AnalyticsParameterKey.errorCategory], .string("scope_denied"))
    }

    func testAnExpiredLoginWhileGrantingOffersToSignInAgain() async {
        let auth = Fixtures.auth()
        auth.additionalScopesResult = .failure(GoogleAuthError.signInExpired(email: Fixtures.email))
        let sut = makeSUT(auth: auth)
        var last: GoogleAccessPrompt?

        let resolved = await sut.resolve(prompt(.permissionNeeded(.remoteConfig))) { last = $0 }

        XCTAssertFalse(resolved)
        XCTAssertEqual(last?.reason, .signInRequired)
        XCTAssertNil(last?.feedback)
    }

    func testOtherGrantErrorsShowAMessage() async {
        struct Unexpected: Error {}
        let auth = Fixtures.auth()
        auth.additionalScopesResult = .failure(Unexpected())
        let sut = makeSUT(auth: auth)
        var last: GoogleAccessPrompt?

        _ = await sut.resolve(prompt(.permissionNeeded(.remoteConfig))) { last = $0 }

        XCTAssertEqual(last?.feedback, String(localized: "Google couldn't complete the request right now. Try again later."))
        XCTAssertEqual(analytics.results(of: .googleScopeGrant), [.failure])
    }

    // MARK: - Sign in again

    func testSigningInAgainReauthenticatesTheSameLogin() async {
        let auth = Fixtures.auth()
        auth.reauthenticateResult = .success(Fixtures.result(scopes: GoogleOAuthScope.signIn))
        let sut = makeSUT(auth: auth)

        let resolved = await sut.resolve(prompt(.signInRequired)) { _ in }

        XCTAssertTrue(resolved)
        XCTAssertEqual(auth.reauthenticateCalls, [Fixtures.loginId])
        XCTAssertTrue(auth.signInCalls.isEmpty, "never a fresh sign-in that could bind another account")
        XCTAssertEqual(analytics.taps(of: .signInAgain).count, 1)
        XCTAssertEqual(analytics.results(of: .googleSignIn), [.success])
    }

    func testAnotherGoogleAccountIsRefusedWithAnExplanation() async {
        let auth = Fixtures.auth()
        auth.reauthenticateResult = .failure(GoogleAuthError.differentAccount(expectedEmail: Fixtures.email))
        let sut = makeSUT(auth: auth)
        var last: GoogleAccessPrompt?

        let resolved = await sut.resolve(prompt(.signInRequired)) { last = $0 }

        XCTAssertFalse(resolved)
        XCTAssertEqual(last?.reason, .signInRequired)
        XCTAssertEqual(last?.feedback, GoogleAuthError.differentAccount(expectedEmail: Fixtures.email).errorDescription)
        XCTAssertTrue(last?.feedback?.contains(Fixtures.email) == true)
        XCTAssertEqual(analytics.results(of: .googleSignIn), [.failure])
    }

    func testCancellingSignInAgainShowsNoError() async {
        let auth = Fixtures.auth()
        auth.reauthenticateResult = .failure(GoogleAuthError.cancelled)
        let sut = makeSUT(auth: auth)
        var last: GoogleAccessPrompt?

        let resolved = await sut.resolve(prompt(.signInRequired)) { last = $0 }

        XCTAssertFalse(resolved)
        XCTAssertNil(last?.feedback)
        XCTAssertEqual(analytics.results(of: .googleSignIn), [.cancelled])
    }

    // MARK: - Helpers

    private func prompt(_ reason: GoogleAccessPrompt.Reason) -> GoogleAccessPrompt {
        GoogleAccessPrompt(reason: reason, email: Fixtures.email)
    }

    private static var scopeInsufficient: APIProviderFirebase.Error {
        let response = try? APIProviderFirebase.jsonDecoder.decode(
            ErrorResponse.self,
            from: Data(ScriptedFirebaseExecutor.scopeInsufficientJSON.utf8)
        )
        return .requestFailure(403, response, nil)
    }
}
