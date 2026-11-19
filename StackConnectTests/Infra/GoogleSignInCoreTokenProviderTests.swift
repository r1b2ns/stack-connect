import XCTest
import StackProtocols
import StackCoreRust
@testable import StackConnect

/// Google Play "Sign in with Google" through the Rust core: the
/// `AccessTokenProvider` adapter (token pass-through, error mapping to the
/// core's contract and back), and which `connect` variant
/// `GooglePlayAccountConnection` picks. No real core, Google or Keychain.
final class GoogleSignInCoreTokenProviderTests: XCTestCase {

    private typealias Fixtures = GooglePlayTestFixtures

    // MARK: - Token pass-through

    func testHandsTheCoreTheLoginsAccessToken() async throws {
        let tokens = RecordingGoogleAccessTokenProvider(result: .success("user-token"))
        let sut = GoogleSignInCoreTokenProvider(loginId: "user-1", tokens: tokens)

        let token = try await sut.accessToken(accountId: "user-1")

        XCTAssertEqual(token, "user-token")
        XCTAssertEqual(tokens.requestedLogins, ["user-1"])
    }

    func testAsksForATokenOnEveryCallWithoutCaching() async throws {
        let tokens = RecordingGoogleAccessTokenProvider(result: .success("user-token"))
        let sut = GoogleSignInCoreTokenProvider(loginId: "user-1", tokens: tokens)

        _ = try await sut.accessToken(accountId: "user-1")
        _ = try await sut.accessToken(accountId: "user-1")

        XCTAssertEqual(tokens.requestedLogins.count, 2, "caching and refreshing is GoogleAuthService's job")
    }

    func testAlwaysUsesItsOwnLogin() async throws {
        let tokens = RecordingGoogleAccessTokenProvider(result: .success("user-token"))
        let sut = GoogleSignInCoreTokenProvider(loginId: "user-1", tokens: tokens)

        _ = try await sut.accessToken(accountId: "someone-else")

        XCTAssertEqual(tokens.requestedLogins, ["user-1"])
    }

    // MARK: - App error → core error

    func testSignInFailuresBecomeMarkedAuthErrors() {
        let cases: [(GoogleAuthError, GoogleSignInCoreAuthMarker.Kind)] = [
            (.invalidGrant, .invalidGrant),
            (.signInExpired(email: "dev@example.com"), .invalidGrant),
            (.loginNotFound, .loginNotFound),
            (.notConfigured, .notConfigured),
            (.http(statusCode: 400, summary: nil), .tokenError),
            (.http(statusCode: 401, summary: nil), .tokenError),
            (.invalidTokenResponse, .tokenError),
            (.noRefreshToken, .tokenError)
        ]
        for (error, kind) in cases {
            guard case .Auth(let message) = GoogleSignInCoreTokenProvider.coreError(for: error) else {
                XCTFail("Expected StackError.Auth for \(error)")
                continue
            }
            XCTAssertEqual(GoogleSignInCoreAuthMarker.kind(in: message), kind, "\(error)")
        }
    }

    func testInvalidGrantKeepsARecognizableMarker() {
        guard case .Auth(let message) = GoogleSignInCoreTokenProvider.coreError(for: GoogleAuthError.invalidGrant) else {
            return XCTFail("Expected StackError.Auth")
        }
        XCTAssertTrue(message.contains("invalid_grant"))
    }

    func testOfflineAndTransientFailuresBecomeNetworkErrors() {
        let errors: [Error] = [
            GoogleAuthError.network(.notConnectedToInternet),
            GoogleAuthError.http(statusCode: 503, summary: nil),
            GoogleAuthError.http(statusCode: 429, summary: nil),
            URLError(.timedOut),
            CancellationError()
        ]
        for error in errors {
            let coreError = GoogleSignInCoreTokenProvider.coreError(for: error)
            guard case .Network = coreError else {
                XCTFail("Expected StackError.Network for \(error), got \(coreError)")
                continue
            }
            XCTAssertTrue(GooglePlayErrorTranslator.isOffline(coreError), "a Play screen keeps its cache")
        }
    }

    func testAnyOtherErrorBecomesAMarkedAuthError() {
        struct Unexpected: Error {}
        guard case .Auth(let message) = GoogleSignInCoreTokenProvider.coreError(for: Unexpected()) else {
            return XCTFail("Expected StackError.Auth")
        }
        XCTAssertEqual(GoogleSignInCoreAuthMarker.kind(in: message), .tokenError)
    }

    func testAccessTokenThrowsTheMappedCoreError() async {
        let sut = GoogleSignInCoreTokenProvider(
            loginId: "user-1",
            tokens: RecordingGoogleAccessTokenProvider(result: .failure(GoogleAuthError.network(.timedOut)))
        )

        do {
            _ = try await sut.accessToken(accountId: "user-1")
            XCTFail("Expected an error")
        } catch StackError.Network {
            // Expected.
        } catch {
            XCTFail("Expected StackError.Network, got \(error)")
        }
    }

    // MARK: - Core error → app error

    func testAMarkedAuthComingBackFromTheCoreIsTheOriginalSignInError() async {
        let sut = GoogleSignInCoreTokenProvider(
            loginId: "user-1",
            tokens: RecordingGoogleAccessTokenProvider(result: .failure(GoogleAuthError.signInExpired(email: "dev@example.com")))
        )
        let fromCore = await coreError(of: sut)

        XCTAssertEqual(sut.signInError(for: fromCore), .signInExpired(email: "dev@example.com"))
    }

    func testASuccessClearsTheRecordedFailureButTheMarkerStillMaps() async throws {
        let tokens = RecordingGoogleAccessTokenProvider(result: .failure(GoogleAuthError.signInExpired(email: "dev@example.com")))
        let sut = GoogleSignInCoreTokenProvider(loginId: "user-1", tokens: tokens)
        let fromCore = await coreError(of: sut)
        tokens.result = .success("new-token")
        _ = try await sut.accessToken(accountId: "user-1")

        XCTAssertEqual(sut.signInError(for: fromCore), .signInExpired(email: nil))
    }

    func testUnmarkedCoreErrorsAreNotSignInErrors() {
        let sut = GoogleSignInCoreTokenProvider(loginId: "user-1", tokens: RecordingGoogleAccessTokenProvider(result: .success("t")))

        XCTAssertNil(sut.signInError(for: .Auth(message: "Google returned 403: The caller does not have permission")))
        XCTAssertNil(sut.signInError(for: .Http(status: 429, message: "quota")))
        XCTAssertNil(sut.signInError(for: .Network(message: "offline")))
    }

    // MARK: - Provider selection in GooglePlayAccountConnection

    func testGoogleSignInAccountsConnectWithTheAccessTokenProvider() async throws {
        let factory = RecordingCoreProviderFactory()
        let tokens = RecordingGoogleAccessTokenProvider(result: .success("user-token"))
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(googleLoginId: "user-1"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: factory,
            googleTokens: tokens
        )

        let apps = try await connection.fetchApps()

        XCTAssertEqual(factory.calls, [.accessToken(accountId: "user-1")])
        XCTAssertEqual(apps.map(\.id), ["com.probe"])
        XCTAssertEqual(factory.receivedTokens, ["user-token"], "the core got the user's token")
        XCTAssertEqual(tokens.requestedLogins, ["user-1"])
    }

    func testServiceAccountsStillConnectWithTheirKeys() async throws {
        let factory = RecordingCoreProviderFactory()
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(serviceAccountJSON: Fixtures.serviceAccountJSON()),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: factory,
            googleTokens: RecordingGoogleAccessTokenProvider(result: .success("unused"))
        )

        _ = try await connection.fetchApps()

        XCTAssertEqual(factory.calls, [.serviceAccount(accountId: Fixtures.clientEmail)])
    }

    func testTheProviderIsBuiltOncePerConnection() async throws {
        let factory = RecordingCoreProviderFactory()
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(googleLoginId: "user-1"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: factory,
            googleTokens: RecordingGoogleAccessTokenProvider(result: .success("user-token"))
        )

        _ = try await connection.fetchApps()
        try await connection.validateCredentials()

        XCTAssertEqual(factory.calls.count, 1)
    }

    func testAnExpiredSignInReachesThePlayScreensAsSignInAgainCopy() async {
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(googleLoginId: "user-1"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: RecordingCoreProviderFactory(),
            googleTokens: RecordingGoogleAccessTokenProvider(result: .failure(GoogleAuthError.signInExpired(email: "dev@example.com")))
        )

        do {
            _ = try await connection.fetchApps()
            XCTFail("Expected the sign-in error")
        } catch {
            XCTAssertEqual(error as? GoogleAuthError, .signInExpired(email: "dev@example.com"))
            XCTAssertEqual(
                GooglePlayErrorTranslator.friendlyMessage(for: error),
                GoogleAuthError.signInExpired(email: "dev@example.com").errorDescription
            )
            XCTAssertEqual(AnalyticsErrorCategory(connectionError: error), .invalidCredentials)
        }
    }

    func testAnOfflineTokenRequestStaysAnOfflineError() async {
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(googleLoginId: "user-1"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: RecordingCoreProviderFactory(),
            googleTokens: RecordingGoogleAccessTokenProvider(result: .failure(GoogleAuthError.network(.notConnectedToInternet)))
        )

        do {
            try await connection.validateCredentials()
            XCTFail("Expected a network error")
        } catch {
            XCTAssertTrue(GooglePlayErrorTranslator.isOffline(error))
        }
    }

    func testGooglePlaysOwnAuthRefusalIsKeptAsIs() async {
        let factory = RecordingCoreProviderFactory()
        factory.googleRefusal = .Auth(message: "Google returned 403: The caller does not have permission")
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(googleLoginId: "user-1"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: factory,
            googleTokens: RecordingGoogleAccessTokenProvider(result: .success("user-token"))
        )

        do {
            _ = try await connection.fetchApps()
            XCTFail("Expected Google's refusal")
        } catch StackError.Auth(let message) {
            XCTAssertEqual(message, "Google returned 403: The caller does not have permission")
        } catch {
            XCTFail("Expected StackError.Auth, got \(error)")
        }
    }

    // MARK: - Rejected tokens (no retry in the core)

    func testGooglePlaysAuthRefusalDropsTheCachedTokenSoTheNextCallRefreshes() async {
        let factory = RecordingCoreProviderFactory()
        factory.googleRefusal = .Auth(message: "Google returned 401: Request had invalid authentication credentials")
        let tokens = RecordingGoogleAccessTokenProvider(result: .success("revoked-token"))
        let connection = GooglePlayAccountConnection(
            credentials: GooglePlayCredentials(googleLoginId: "user-1"),
            connectivity: MockConnectivityProviding(online: true),
            coreProviders: factory,
            googleTokens: tokens
        )

        _ = try? await connection.fetchApps()

        XCTAssertEqual(tokens.invalidatedLogins, ["user-1"])
        XCTAssertEqual(tokens.requestedLogins, ["user-1"], "no automatic retry")
    }

    func testOwnSignInFailuresAndHttpErrorsKeepTheCachedToken() async {
        let tokens = RecordingGoogleAccessTokenProvider(result: .success("token"))
        let sut = GoogleSignInCoreTokenProvider(loginId: "user-1", tokens: tokens)

        await sut.tokenRejected(by: GoogleSignInCoreTokenProvider.coreError(for: GoogleAuthError.invalidGrant))
        await sut.tokenRejected(by: .Http(status: 404, message: "Not found"))
        await sut.tokenRejected(by: .Network(message: "offline"))

        XCTAssertTrue(tokens.invalidatedLogins.isEmpty)
    }

    // MARK: - Helpers

    /// Runs one token request that fails and returns the error as the core
    /// hands it back (an `Auth` message is kept verbatim).
    private func coreError(of sut: GoogleSignInCoreTokenProvider) async -> StackError {
        do {
            _ = try await sut.accessToken(accountId: sut.loginId)
            XCTFail("Expected the token request to fail")
            return .Auth(message: "")
        } catch let error as StackError {
            return error
        } catch {
            XCTFail("Expected a StackError, got \(error)")
            return .Auth(message: "")
        }
    }
}

// MARK: - Test doubles

/// A scripted `GoogleAccessTokenProviding` that records each login asked for.
private final class RecordingGoogleAccessTokenProvider: GoogleAccessTokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<String, Error>
    private var _requestedLogins: [String] = []

    init(result: Result<String, Error>) {
        _result = result
    }

    var result: Result<String, Error> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    var requestedLogins: [String] { lock.withLock { _requestedLogins } }

    private var _invalidatedLogins: [String] = []
    var invalidatedLogins: [String] { lock.withLock { _invalidatedLogins } }

    func accessToken(forLogin loginId: String) async throws -> String {
        let result = lock.withLock {
            _requestedLogins.append(loginId)
            return _result
        }
        return try result.get()
    }

    func invalidateAccessToken(forLogin loginId: String) async {
        lock.withLock { _invalidatedLogins.append(loginId) }
    }
}

/// Records which `connect` variant a connection used. The access-token
/// provider it returns asks the token provider before each call, as the core
/// does, and passes token failures back as the core would.
private final class RecordingCoreProviderFactory: CoreProviderMaking, @unchecked Sendable {

    enum Call: Equatable {
        case serviceAccount(accountId: String)
        case accessToken(accountId: String)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _receivedTokens: [String] = []
    /// Thrown by Google (through the core) after a successful token request.
    var googleRefusal: StackError?

    var calls: [Call] { lock.withLock { _calls } }
    var receivedTokens: [String] { lock.withLock { _receivedTokens } }

    func connect(kind: ServiceKind, accountId: String, store: CredentialStore, debugLogger: DebugLogger?) throws -> StackCoreRust.Provider {
        lock.withLock { _calls.append(.serviceAccount(accountId: accountId)) }
        return FakeCoreProvider(kind: kind)
    }

    func connectWithAccessToken(
        kind: ServiceKind,
        accountId: String,
        tokenProvider: AccessTokenProvider,
        debugLogger: DebugLogger?
    ) throws -> StackCoreRust.Provider {
        lock.withLock { _calls.append(.accessToken(accountId: accountId)) }
        return TokenProbingProvider(accountId: accountId, tokenProvider: tokenProvider) { [weak self] token in
            guard let self else { return }
            let refusal = self.lock.withLock {
                self._receivedTokens.append(token)
                return self.googleRefusal
            }
            if let refusal { throw refusal }
        }
    }

    func connectWithAppleSession(accountId: String, teamId: UInt64, sessionStore: SessionStore, debugLogger: DebugLogger?) throws -> StackCoreRust.Provider {
        throw StackError.Unsupported(message: "Not used by these tests")
    }

    func makeSyncService(provider: StackCoreRust.Provider, store: BlobStore, accountId: String) -> StackCoreRust.SyncService {
        fatalError("Not used by these tests")
    }
}

/// A core provider that, like the real one, asks for a token before each
/// request: a `StackError` passes through, anything else becomes `Auth`.
private final class TokenProbingProvider: FakeCoreProvider, @unchecked Sendable {

    private let accountId: String
    private let tokenProvider: AccessTokenProvider
    private let send: (String) throws -> Void

    init(accountId: String, tokenProvider: AccessTokenProvider, send: @escaping (String) throws -> Void) {
        self.accountId = accountId
        self.tokenProvider = tokenProvider
        self.send = send
        super.init(kind: .googlePlay)
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Never lifted from the FFI")
    }

    private func authorizedRequest() async throws {
        let token: String
        do {
            token = try await tokenProvider.accessToken(accountId: accountId)
        } catch let error as StackError {
            throw error
        } catch {
            throw StackError.Auth(message: error.localizedDescription)
        }
        try send(token)
    }

    override func validate() async throws {
        try await authorizedRequest()
    }

    override func fetchApps() async throws -> [StackCoreRust.AppInfo] {
        try await authorizedRequest()
        return [StackCoreRust.AppInfo(id: "com.probe", name: "Probe", bundleId: "com.probe", platform: "ANDROID")]
    }
}
