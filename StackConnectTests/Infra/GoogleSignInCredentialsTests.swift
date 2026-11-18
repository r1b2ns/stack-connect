import XCTest
import APIProviderFirebase
import StackCoreRust
@testable import StackConnect

/// The Google sign-in credential kind next to the service account (plan
/// Phase 2): Keychain shape, how the Firebase and Play providers pick a token,
/// the account picker's listing, export (G7) and deletion.
@MainActor
final class GoogleSignInCredentialsTests: XCTestCase {

    // MARK: - Keychain shape

    func testItemsStoredBeforeGoogleSignInDecodeAsServiceAccounts() throws {
        let legacy = Data(#"{"serviceAccountJSON":"{\"type\":\"service_account\"}"}"#.utf8)

        let play = try JSONDecoder().decode(GooglePlayCredentials.self, from: legacy)
        let firebase = try JSONDecoder().decode(FirebaseCredentials.self, from: legacy)

        XCTAssertEqual(play.source, .serviceAccount(json: #"{"type":"service_account"}"#))
        XCTAssertEqual(firebase.source, .serviceAccount(json: #"{"type":"service_account"}"#))
        XCTAssertFalse(play.isGoogleSignIn)
    }

    func testServiceAccountItemsKeepTheirHistoricShape() throws {
        let data = try JSONEncoder().encode(GooglePlayCredentials(serviceAccountJSON: "{}"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object.keys.sorted(), ["serviceAccountJSON"])
    }

    func testGoogleSignInItemsRoundTripWithoutAnySecret() throws {
        let keychain = MockKeyStorable()
        keychain.setObject(FirebaseCredentials(googleLoginId: "user-1"), forKey: "credentials.a")
        keychain.setObject(GooglePlayCredentials(googleLoginId: "user-1"), forKey: "credentials.b")

        let firebase: FirebaseCredentials? = keychain.object(forKey: "credentials.a")
        let play: GooglePlayCredentials? = keychain.object(forKey: "credentials.b")

        XCTAssertEqual(firebase?.source, .googleSignIn(loginId: "user-1"))
        XCTAssertEqual(play?.source, .googleSignIn(loginId: "user-1"))
        let raw = try XCTUnwrap(keychain.data(forKey: "credentials.b"))
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("refresh"), "the refresh token lives in the login's own item")
    }

    func testAccountsDecodedWithoutAuthMethodAreKeyFileAccounts() throws {
        let account = AccountModel(name: "Old", providerType: .googlePlay)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(account)) as? [String: Any])
        object["authMethod"] = nil
        let decoded = try JSONDecoder().decode(AccountModel.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertEqual(decoded.authMethod, .keyFile)
        XCTAssertEqual(account.updating(name: "New").authMethod, .keyFile)
        XCTAssertEqual(AccountModel(name: "G", providerType: .firebase, authMethod: .googleSignIn).updating(name: "H").authMethod, .googleSignIn)
    }

    // MARK: - Firebase: token selection

    func testFirebaseServiceAccountCredentialsUseTheServiceAccountProvider() {
        let factory = RecordingFirebaseProviderFactory()

        _ = factory.makeProvider(credentials: FirebaseCredentials(serviceAccountJSON: "not json"))

        XCTAssertEqual(factory.serviceAccountCalls, 0, "an unusable JSON builds nothing")
        XCTAssertTrue(factory.authenticators.isEmpty, "a service account never goes through Google sign-in")
    }

    func testFirebaseGoogleSignInCredentialsSendTheUsersBearerToken() async throws {
        let factory = RecordingFirebaseProviderFactory()
        let provider = factory.makeProvider(
            credentials: FirebaseCredentials(googleLoginId: "user-1"),
            tokens: StaticGoogleAccessTokenProvider(token: "user-token")
        )

        XCTAssertNotNil(provider)
        let authenticator = try XCTUnwrap(factory.authenticators.first)
        let adapted = try await authenticator.adapt(URLRequest(url: GoogleOAuthEndpoint.firebaseProjects))
        XCTAssertEqual(adapted.value(forHTTPHeaderField: "Authorization"), "Bearer user-token")
    }

    func testFirebaseGoogleSignInErrorsReachTheScreenUnchanged() async {
        let executor = RecordingRequestExecutor()
        let provider = APIProviderFirebase(
            authenticator: GoogleSignInRequestAuthenticator(
                loginId: "user-1",
                tokens: StaticGoogleAccessTokenProvider(error: .signInExpired(email: "dev@example.com"))
            ),
            requestExecutor: executor
        )

        do {
            _ = try await provider.request(FirebaseAPI.v1beta1.projects.get())
            XCTFail("Expected the sign-in error")
        } catch {
            XCTAssertEqual(error as? GoogleAuthError, .signInExpired(email: "dev@example.com"))
        }
        XCTAssertEqual(executor.requestCount, 0)
    }

    // MARK: - Google Play: credential kind → core auth path

    func testGooglePlayGoogleSignInCredentialsReachTheCoreWithTheUsersToken() async {
        // No core fake: the real core is reached and asks for the token, which
        // fails here before any request is sent to Google.
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(googleLoginId: "user-1"),
            connectivity: MockConnectivityProviding(online: true),
            googleTokens: StaticGoogleAccessTokenProvider(error: .signInExpired(email: "dev@example.com"))
        )

        do {
            _ = try await connection.fetchApps()
            XCTFail("Expected the sign-in error")
        } catch {
            XCTAssertEqual(error as? GoogleAuthError, .signInExpired(email: "dev@example.com"))
            XCTAssertEqual(GooglePlayErrorTranslator.friendlyMessage(for: error), GoogleAuthError.signInExpired(email: "dev@example.com").errorDescription)
        }
    }

    func testGooglePlayServiceAccountCredentialsStillReachTheCore() async {
        // An unusable key fails in the service-account parse, never asks for
        // a Google sign-in token.
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(serviceAccountJSON: ""),
            connectivity: MockConnectivityProviding(online: true),
            googleTokens: StaticGoogleAccessTokenProvider(error: .loginNotFound)
        )

        do {
            _ = try await connection.fetchApps()
            XCTFail("Expected a parse error")
        } catch {
            XCTAssertNil(error as? GoogleAuthError)
            XCTAssertEqual(error as? GooglePlayServiceAccount.ParseError, .empty)
        }
    }

    // MARK: - Account picker listing

    func testPlayAppsAreListedWithTheUsersTokenAcrossPages() async throws {
        let http = MockGoogleHTTPClient()
        http.respond(to: "apps:search?pageSize=100&pageToken=p2", json: ["apps": [["packageName": "com.b", "displayName": "Beta"]]])
        http.respond(to: "apps:search?pageSize=100", json: [
            "apps": [["packageName": "com.a", "displayName": "Alpha"], ["packageName": "com.c"]],
            "nextPageToken": "p2"
        ], once: true)
        let directory = GoogleResourceDirectory(tokens: StaticGoogleAccessTokenProvider(token: "user-token"), http: http)

        let apps = try await directory.playApps(loginId: "user-1")

        XCTAssertEqual(apps.map(\.id), ["com.a", "com.b", "com.c"])
        XCTAssertEqual(apps.map(\.title), ["Alpha", "Beta", "com.c"])
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(http.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer user-token")
    }

    func testFirebaseProjectsSkipDeletedOnes() async throws {
        let http = MockGoogleHTTPClient()
        http.respond(to: "v1beta1/projects", json: ["results": [
            ["projectId": "alpha-1", "displayName": "Alpha", "state": "ACTIVE"],
            ["projectId": "gone", "displayName": "Gone", "state": "DELETED"],
            ["projectId": "beta", "displayName": "beta"]
        ]])
        let directory = GoogleResourceDirectory(tokens: StaticGoogleAccessTokenProvider(), http: http)

        let projects = try await directory.firebaseProjects(loginId: "user-1")

        XCTAssertEqual(projects, [
            GoogleAccessibleResource(id: "alpha-1", title: "Alpha", subtitle: "alpha-1"),
            GoogleAccessibleResource(id: "beta", title: "beta", subtitle: nil)
        ])
    }

    func testListingSurfacesServiceDisabledAsAGoogleError() async {
        let http = MockGoogleHTTPClient()
        http.respond(to: "apps:search", status: 403, json: ["error": [
            "code": 403, "status": "PERMISSION_DENIED", "details": [["reason": "SERVICE_DISABLED"]]
        ]])
        let directory = GoogleResourceDirectory(tokens: StaticGoogleAccessTokenProvider(), http: http)

        do {
            _ = try await directory.playApps(loginId: "user-1")
            XCTFail("Expected an error")
        } catch let error as GoogleAuthError {
            XCTAssertTrue(error.isServiceDisabled)
            XCTAssertEqual(AnalyticsErrorCategory(connectionError: error), .server)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    // MARK: - Export (G7)

    func testGoogleSignInAccountsAreNeverExported() throws {
        let keychain = MockKeyStorable()
        let account = AccountModel(name: "Play", providerType: .googlePlay, authMethod: .googleSignIn)
        keychain.setObject(GooglePlayCredentials(googleLoginId: "user-1"), forKey: "credentials.\(account.id)")

        XCTAssertFalse(account.isExportable)
        XCTAssertNil(AccountTransferCredentials.exportPayload(for: account, keychain: keychain))
        XCTAssertThrowsError(try AccountExporter(keychain: keychain).export(AccountExportRequest(
            account: account, exportName: "x", rules: .allPermissions, password: "password-1", expirationDate: nil, appsBundles: nil
        ))) { error in
            XCTAssertEqual(error as? AccountExportError, .notExportable)
        }
    }

    func testServiceAccountPlayAccountsStillExport() {
        let keychain = MockKeyStorable()
        let account = AccountModel(name: "Play", providerType: .googlePlay)
        keychain.setObject(GooglePlayCredentials(serviceAccountJSON: "{json}"), forKey: "credentials.\(account.id)")

        XCTAssertTrue(account.isExportable)
        XCTAssertEqual(AccountTransferCredentials.exportPayload(for: account, keychain: keychain), ["serviceAccountJSON": "{json}"])
    }

    // MARK: - Deletion releases the login

    func testDeletingTheLastAccountOfALoginSignsItOut() async throws {
        let storage = MockPersistentStorable()
        let keychain = MockKeyStorable()
        let auth = MockGoogleAuthService()
        let first = AccountModel(name: "A", providerType: .firebase, appsBundles: ["a"], authMethod: .googleSignIn)
        let second = AccountModel(name: "B", providerType: .firebase, appsBundles: ["b"], authMethod: .googleSignIn)
        for account in [first, second] {
            try await storage.save(account, id: account.id)
            keychain.setObject(FirebaseCredentials(googleLoginId: "user-1"), forKey: "credentials.\(account.id)")
        }

        try await AccountCascadeDeleter.delete(first, storage: storage, keychain: keychain, googleAuth: auth)
        XCTAssertEqual(auth.signOutCalls, [], "the other account still uses the login")

        try await AccountCascadeDeleter.delete(second, storage: storage, keychain: keychain, googleAuth: auth)
        XCTAssertEqual(auth.signOutCalls, ["user-1"])
    }

    func testDeletingAServiceAccountAccountSignsNothingOut() async throws {
        let storage = MockPersistentStorable()
        let keychain = MockKeyStorable()
        let auth = MockGoogleAuthService()
        let account = AccountModel(name: "A", providerType: .firebase)
        try await storage.save(account, id: account.id)
        keychain.setObject(FirebaseCredentials(serviceAccountJSON: "{}"), forKey: "credentials.\(account.id)")

        try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain, googleAuth: auth)

        XCTAssertEqual(auth.signOutCalls, [])
    }
}

// MARK: - Helpers

/// Records which kind of provider `makeProvider(credentials:)` asked for.
private final class RecordingFirebaseProviderFactory: FirebaseProviderMaking, @unchecked Sendable {
    private(set) var serviceAccountCalls = 0
    private(set) var authenticators: [RequestAuthenticating] = []

    func makeProvider(configuration: FirebaseConfiguration) -> APIProviderFirebase {
        serviceAccountCalls += 1
        return APIProviderFirebase(configuration: configuration)
    }

    func makeProvider(authenticator: RequestAuthenticating) -> APIProviderFirebase {
        authenticators.append(authenticator)
        return APIProviderFirebase(authenticator: authenticator, requestExecutor: RecordingRequestExecutor())
    }
}

private final class RecordingRequestExecutor: RequestExecutor, @unchecked Sendable {
    private(set) var requestCount = 0

    func execute(_ urlRequest: URLRequest, completion: @escaping (Result<Response<Data>, Swift.Error>) -> Void) {
        requestCount += 1
        completion(.success(Response(requestURL: urlRequest.url, statusCode: 500, data: Data())))
    }
}
