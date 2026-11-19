import XCTest
import APIProviderFirebase
@testable import StackConnect

/// The Firebase screens of a "Sign in with Google" account (plan Phase 3,
/// R5): Remote Config and Analytics ask for their sensitive scope before any
/// request, every screen offers "Sign in again" for an expired login, and a
/// token Google rejects early is dropped and retried once. Requests go through
/// the real `APIProviderFirebase` and `GoogleSignInRequestAuthenticator` with a
/// scripted executor; service-account accounts behave as before.
@MainActor
final class FirebaseGoogleSignInScreensTests: XCTestCase {

    private typealias Fixtures = GoogleSignInFirebaseFixtures

    private var previousProviders: (any FirebaseProviderMaking)!
    private var executor: ScriptedFirebaseExecutor!
    private var keychain: MockKeyStorable!
    private var analytics: MockAnalyticsTracker!
    private let account = GoogleSignInFirebaseFixtures.account()
    private let project = GoogleSignInFirebaseFixtures.project

    override func setUp() async throws {
        try await super.setUp()
        previousProviders = BackendEnvironment.firebaseProviders
        executor = ScriptedFirebaseExecutor { request in
            Self.answer(request)
        }
        BackendEnvironment.firebaseProviders = ScriptedFirebaseProviderFactory(executor: executor)
        keychain = MockKeyStorable()
        analytics = MockAnalyticsTracker()
        Fixtures.storeCredentials(for: account, in: keychain)
    }

    override func tearDown() async throws {
        BackendEnvironment.firebaseProviders = previousProviders
        previousProviders = nil
        executor = nil
        keychain = nil
        analytics = nil
        try await super.tearDown()
    }

    // MARK: - Remote Config: scope first (A1, A2)

    func testRemoteConfigWithoutTheScopeExplainsAndCallsNoAPI() async {
        let sut = remoteConfig(auth: Fixtures.auth())

        await sut.load()

        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .permissionNeeded(.remoteConfig))
        XCTAssertNil(sut.uiState.error)
        XCTAssertTrue(executor.requests.isEmpty, "no request for a certain 403")
    }

    func testGrantingRemoteConfigAccessReloadsTheTemplate() async {
        let auth = Fixtures.auth()
        auth.additionalScopesResult = .success(Fixtures.result(scopes: GoogleOAuthScope.signIn + [GoogleOAuthScope.cloudPlatform]))
        let sut = remoteConfig(auth: auth)
        await sut.load()

        await sut.resolveGoogleAccess()

        XCTAssertNil(sut.uiState.googleAccessPrompt)
        XCTAssertEqual(sut.uiState.parameters.map(\.name), ["welcome_flag"])
        XCTAssertEqual(auth.additionalScopesCalls.map(\.scopes), [[GoogleOAuthScope.cloudPlatform]])
    }

    func testCancellingTheGrantKeepsTheExplanationWithoutError() async {
        let auth = Fixtures.auth()
        auth.additionalScopesResult = .failure(GoogleAuthError.cancelled)
        let sut = remoteConfig(auth: auth)
        await sut.load()

        await sut.resolveGoogleAccess()

        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .permissionNeeded(.remoteConfig))
        XCTAssertNil(sut.uiState.googleAccessPrompt?.feedback)
        XCTAssertNil(sut.uiState.error)
        XCTAssertTrue(executor.requests.isEmpty)
    }

    func testAScopeRevokedElsewhereFallsBackToTheExplanation() async {
        executor.handler = { _ in (403, ScriptedFirebaseExecutor.scopeInsufficientJSON) }
        let sut = remoteConfig(auth: Fixtures.auth(extraScopes: [GoogleOAuthScope.cloudPlatform]))

        await sut.load()

        XCTAssertEqual(executor.requests.count, 1)
        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .permissionNeeded(.remoteConfig))
        XCTAssertNil(sut.uiState.error)
    }

    func testAServiceAccountLoadsRemoteConfigAsBefore() async {
        let serviceAccount = AccountModel(id: FakeDataSeeder.AccountID.northwindFirebase, name: "Northwind Labs", providerType: .firebase)
        FakeDataSeeder.writeCredentials(into: keychain)
        let auth = Fixtures.auth()
        let sut = RemoteConfigViewModel(project: project, account: serviceAccount, keychain: keychain, analytics: analytics, googleAuth: auth)

        await sut.load()

        XCTAssertNil(sut.uiState.googleAccessPrompt)
        XCTAssertEqual(sut.uiState.parameters.map(\.name), ["welcome_flag"])
        XCTAssertEqual(executor.bearerTokens, ["fake-data-token"])
        XCTAssertTrue(auth.additionalScopesCalls.isEmpty)
    }

    func testAnExpiredSignInWhilePublishingKeepsTheEdits() async {
        let auth = Fixtures.auth(extraScopes: [GoogleOAuthScope.cloudPlatform])
        let sut = remoteConfig(auth: auth)
        await sut.load()
        sut.addParameter("new_flag", parameter: RemoteConfigParameter(defaultValue: .init(value: "1")))
        auth.accessTokenResult = .failure(GoogleAuthError.signInExpired(email: Fixtures.email))
        auth.reauthenticateResult = .success(Fixtures.result(scopes: GoogleOAuthScope.signIn + [GoogleOAuthScope.cloudPlatform]))

        await sut.saveTemplate()
        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .signInRequired)
        let requestsBefore = executor.requests.count
        await sut.resolveGoogleAccess()

        XCTAssertNil(sut.uiState.googleAccessPrompt)
        XCTAssertEqual(executor.requests.count, requestsBefore, "no reload: it would drop the unpublished edit")
        XCTAssertTrue(sut.uiState.parameters.contains { $0.name == "new_flag" })
    }

    // MARK: - Analytics: scope first (A1)

    func testAnalyticsWithoutTheScopeExplainsAndCallsNoAPI() async {
        let sut = analyticsDashboard(auth: Fixtures.auth())

        await sut.load()

        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .permissionNeeded(.analytics))
        XCTAssertTrue(executor.requests.isEmpty)
    }

    func testGrantedAnalyticsScopeLoadsTheReport() async {
        let sut = analyticsDashboard(auth: Fixtures.auth(extraScopes: [GoogleOAuthScope.analyticsReadOnly]))

        await sut.load()

        XCTAssertNil(sut.uiState.googleAccessPrompt)
        XCTAssertNil(sut.uiState.error)
        XCTAssertEqual(sut.uiState.propertyId, "123")
        XCTAssertEqual(sut.uiState.currentDAU, 7)
    }

    func testAnalyticsScopeRevokedElsewhereFallsBackToTheExplanation() async {
        executor.handler = { request in
            request.url?.absoluteString.contains(":runReport") == true
                ? (403, ScriptedFirebaseExecutor.scopeInsufficientJSON)
                : Self.answer(request)
        }
        let sut = analyticsDashboard(auth: Fixtures.auth(extraScopes: [GoogleOAuthScope.analyticsReadOnly]))

        await sut.load()

        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .permissionNeeded(.analytics))
        XCTAssertNil(sut.uiState.error)
    }

    // MARK: - Sign in again (B1)

    func testProjectListOffersToSignInAgainAndReloads() async {
        let auth = Fixtures.auth()
        auth.accessTokenResult = .failure(GoogleAuthError.signInExpired(email: Fixtures.email))
        let sut = FirebaseProjectListViewModel(account: account, keychain: keychain, analytics: analytics, googleAuth: auth)
        await sut.load()
        XCTAssertEqual(sut.uiState.googleAccessPrompt, GoogleAccessPrompt(reason: .signInRequired, email: Fixtures.email))
        XCTAssertNil(sut.uiState.error)

        auth.accessTokenResult = .success("fresh-token")
        auth.reauthenticateResult = .success(Fixtures.result(scopes: GoogleOAuthScope.signIn))
        await sut.resolveGoogleAccess()

        XCTAssertEqual(auth.reauthenticateCalls, [Fixtures.loginId])
        XCTAssertNil(sut.uiState.googleAccessPrompt)
        XCTAssertEqual(sut.uiState.projects.map(\.projectId), ["demo-project"])
    }

    func testSigningInWithAnotherAccountIsRefused() async {
        let auth = Fixtures.auth()
        auth.accessTokenResult = .failure(GoogleAuthError.signInExpired(email: Fixtures.email))
        auth.reauthenticateResult = .failure(GoogleAuthError.differentAccount(expectedEmail: Fixtures.email))
        let sut = FirebaseProjectListViewModel(account: account, keychain: keychain, analytics: analytics, googleAuth: auth)
        await sut.load()

        await sut.resolveGoogleAccess()

        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .signInRequired)
        XCTAssertEqual(sut.uiState.googleAccessPrompt?.feedback, GoogleAuthError.differentAccount(expectedEmail: Fixtures.email).errorDescription)
        XCTAssertTrue(executor.requests.isEmpty)
    }

    func testAppListShowsSignInAgainInsteadOfAnEmptyList() async {
        let auth = Fixtures.auth()
        auth.accessTokenResult = .failure(GoogleAuthError.invalidGrant)
        let sut = FirebaseAppListViewModel(account: account, project: project, keychain: keychain, analytics: analytics, googleAuth: auth)

        await sut.load()

        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .signInRequired)
        XCTAssertNil(sut.uiState.error)
    }

    func testMessagingReportsOfferToSignInAgain() async {
        let auth = Fixtures.auth()
        auth.accessTokenResult = .failure(GoogleAuthError.signInExpired(email: Fixtures.email))
        let sut = MessagingViewModel(project: project, account: account, keychain: keychain, storage: MockPersistentStorable(),
                                     analytics: analytics, googleAuth: auth)

        await sut.loadReports()

        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .signInRequired)
        XCTAssertNil(sut.uiState.reportError)
    }

    func testRemoteConfigOffersToSignInAgainForAnExpiredLogin() async {
        let auth = Fixtures.auth(extraScopes: [GoogleOAuthScope.cloudPlatform])
        auth.accessTokenResult = .failure(GoogleAuthError.signInExpired(email: Fixtures.email))
        let sut = remoteConfig(auth: auth)

        await sut.load()

        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .signInRequired)
    }

    // MARK: - Early-revoked token (B2)

    func testA401DropsTheTokenAndRetriesOnceWithAFreshOne() async {
        executor.handler = { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer revoked"
                ? (401, ScriptedFirebaseExecutor.unauthorizedJSON)
                : Self.answer(request)
        }
        let auth = Fixtures.auth()
        auth.accessTokenResult = .success("revoked")
        auth.accessTokenAfterInvalidation = .success("fresh")
        let sut = FirebaseProjectListViewModel(account: account, keychain: keychain, analytics: analytics, googleAuth: auth)

        await sut.load()

        XCTAssertEqual(auth.invalidatedLogins, [Fixtures.loginId])
        XCTAssertEqual(executor.bearerTokens, ["revoked", "fresh"])
        XCTAssertEqual(sut.uiState.projects.map(\.projectId), ["demo-project"])
        XCTAssertNil(sut.uiState.googleAccessPrompt)
    }

    func testA401WhoseRefreshIsRejectedAsksToSignInAgain() async {
        executor.handler = { _ in (401, ScriptedFirebaseExecutor.unauthorizedJSON) }
        let auth = Fixtures.auth()
        auth.accessTokenResult = .success("revoked")
        auth.accessTokenAfterInvalidation = .failure(GoogleAuthError.signInExpired(email: Fixtures.email))
        let sut = FirebaseProjectListViewModel(account: account, keychain: keychain, analytics: analytics, googleAuth: auth)

        await sut.load()

        XCTAssertEqual(executor.requests.count, 1, "the retry never got a token")
        XCTAssertEqual(sut.uiState.googleAccessPrompt?.reason, .signInRequired)
    }

    func testASecond401IsNotRetriedAgain() async {
        executor.handler = { _ in (401, ScriptedFirebaseExecutor.unauthorizedJSON) }
        let auth = Fixtures.auth()
        auth.accessTokenAfterInvalidation = .success("fresh")
        let sut = FirebaseProjectListViewModel(account: account, keychain: keychain, analytics: analytics, googleAuth: auth)

        await sut.load()

        XCTAssertEqual(executor.requests.count, 2, "one retry only")
        XCTAssertNotNil(sut.uiState.error)
        XCTAssertNil(sut.uiState.googleAccessPrompt)
    }

    func testServiceAccountsAreNotRetriedOn401() async {
        executor.handler = { _ in (401, ScriptedFirebaseExecutor.unauthorizedJSON) }
        let serviceAccount = AccountModel(id: FakeDataSeeder.AccountID.northwindFirebase, name: "Northwind Labs", providerType: .firebase)
        FakeDataSeeder.writeCredentials(into: keychain)
        let sut = FirebaseProjectListViewModel(account: serviceAccount, keychain: keychain, analytics: analytics, googleAuth: Fixtures.auth())

        await sut.load()

        XCTAssertEqual(executor.requests.count, 1)
        XCTAssertNotNil(sut.uiState.error)
        XCTAssertNil(sut.uiState.googleAccessPrompt)
    }

    // MARK: - SERVICE_DISABLED in StackConnect's own project

    func testAnalyticsServiceDisabledForASignInAccountHidesTheActivationLink() async {
        executor.handler = { request in
            request.url?.absoluteString.contains(":runReport") == true
                ? (403, ScriptedFirebaseExecutor.serviceDisabledJSON)
                : Self.answer(request)
        }
        let sut = analyticsDashboard(auth: Fixtures.auth(extraScopes: [GoogleOAuthScope.analyticsReadOnly]))

        await sut.load()

        XCTAssertNil(sut.uiState.apiActivationURL, "StackConnect's project: the user can't enable it")
        XCTAssertEqual(sut.uiState.error, GoogleAccessRecovery.unavailableMessage)
        XCTAssertNil(sut.uiState.googleAccessPrompt)
    }

    func testAnalyticsServiceDisabledForAServiceAccountKeepsTheActivationLink() async {
        executor.handler = { request in
            request.url?.absoluteString.contains(":runReport") == true
                ? (403, ScriptedFirebaseExecutor.serviceDisabledJSON)
                : Self.answer(request)
        }
        let serviceAccount = AccountModel(id: FakeDataSeeder.AccountID.northwindFirebase, name: "Northwind Labs", providerType: .firebase)
        FakeDataSeeder.writeCredentials(into: keychain)
        let sut = AnalyticsDashboardViewModel(project: project, account: serviceAccount, keychain: keychain, analytics: analytics, googleAuth: Fixtures.auth())

        await sut.load()

        XCTAssertNotNil(sut.uiState.apiActivationURL)
        XCTAssertEqual(sut.uiState.error, String(localized: "The Google Analytics Data API is not enabled for this project. Enable it in the Google Cloud Console to view analytics."))
    }

    func testMessagingReportsServiceDisabledForASignInAccountHidesTheActivationLink() async {
        executor.handler = { request in
            // Delivery data lives under `androidApps/{appId}/deliveryData`.
            request.url?.absoluteString.contains("deliveryData") == true
                ? (403, ScriptedFirebaseExecutor.serviceDisabledJSON)
                : (200, #"{"apps": [{"appId": "1:1:android:a", "packageName": "com.a"}, {"appId": "1:1:android:b", "packageName": "com.b"}]}"#)
        }
        let sut = MessagingViewModel(project: project, account: account, keychain: keychain, storage: MockPersistentStorable(),
                                     analytics: analytics, googleAuth: Fixtures.auth())

        await sut.loadReports()

        XCTAssertNil(sut.uiState.reportApiActivationURL)
        XCTAssertEqual(sut.uiState.reportError, GoogleAccessRecovery.unavailableMessage)
        XCTAssertEqual(executor.requests.count, 2, "stops after the first disabled API (same for every app)")
    }

    func testRemoteConfigAndListsShowTheGenericMessageForASignInAccount() async {
        executor.handler = { _ in (403, ScriptedFirebaseExecutor.serviceDisabledJSON) }
        let auth = Fixtures.auth(extraScopes: [GoogleOAuthScope.cloudPlatform])
        let config = remoteConfig(auth: auth)
        let projects = FirebaseProjectListViewModel(account: account, keychain: keychain, analytics: analytics, googleAuth: auth)
        let apps = FirebaseAppListViewModel(account: account, project: project, keychain: keychain, analytics: analytics, googleAuth: auth)

        await config.load()
        await projects.load()
        await apps.load()

        XCTAssertEqual(config.uiState.error, GoogleAccessRecovery.unavailableMessage)
        XCTAssertEqual(projects.uiState.error, GoogleAccessRecovery.unavailableMessage)
        XCTAssertEqual(apps.uiState.error, GoogleAccessRecovery.unavailableMessage, "not an empty list")
    }

    // MARK: - Helpers

    private func remoteConfig(auth: MockGoogleAuthService) -> RemoteConfigViewModel {
        RemoteConfigViewModel(project: project, account: account, keychain: keychain, analytics: analytics, googleAuth: auth)
    }

    private func analyticsDashboard(auth: MockGoogleAuthService) -> AnalyticsDashboardViewModel {
        AnalyticsDashboardViewModel(project: project, account: account, keychain: keychain, analytics: analytics, googleAuth: auth)
    }

    /// Minimal Firebase answers for the screens under test.
    private nonisolated static func answer(_ request: URLRequest) -> (status: Int, json: String) {
        let url = request.url?.absoluteString ?? ""
        if url.contains("remoteConfig") {
            return (200, #"{"parameters": {"welcome_flag": {"defaultValue": {"value": "on"}}}}"#)
        }
        if url.contains("analyticsDetails") {
            return (200, #"{"analyticsProperty": {"id": "123", "displayName": "Demo"}}"#)
        }
        if url.contains(":runReport") {
            return (200, #"{"rows": [{"dimensionValues": [{"value": "20261118"}], "metricValues": [{"value": "7"}, {"value": "20"}, {"value": "40"}]}]}"#)
        }
        if url.contains("Apps") {
            return (200, #"{"apps": []}"#)
        }
        if url.contains("/projects") {
            return (200, #"{"results": [{"projectId": "demo-project", "displayName": "Demo", "name": "projects/demo-project"}]}"#)
        }
        return (404, "{}")
    }
}
