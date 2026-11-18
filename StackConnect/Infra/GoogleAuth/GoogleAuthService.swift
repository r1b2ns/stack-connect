import Foundation
import StackProtocols

// MARK: - Results

/// The outcome of an interactive authorization. No token values: only what
/// the UI may show and keep.
struct GoogleSignInResult: Equatable, Sendable {
    let login: GoogleLogin
    /// The scopes this authorization asked for.
    let requestedScopes: [String]
    /// The requested scopes Google did not grant (an unticked checkbox on the
    /// consent page, plan R4), in request order.
    let missingScopes: [String]
    /// `false` when the user signed in again with a login already on the
    /// device: its accounts keep working with the new grant (plan R5).
    let isNewLogin: Bool
}

// MARK: - Protocol

/// "Sign in with Google" for the Firebase and Google Play providers (plan
/// Phase 2): interactive sign-in, incremental scope requests, access tokens
/// for API calls, scope checks and sign-out.
///
/// One login is one Google user (`GoogleLogin.loginId` is Google's `sub`),
/// shared by every account added with it (plan G5).
@MainActor
protocol GoogleAuthServicing: AnyObject, GoogleAccessTokenProviding {
    /// Whether the build has an OAuth client ID.
    var isConfigured: Bool { get }

    /// Opens Google's sign-in page for `scopes`. Signing in with a Google user
    /// already on the device replaces that login's grant.
    func signIn(scopes: [String]) async throws -> GoogleSignInResult

    /// Incremental authorization (plan G3): asks the user of `loginId` for
    /// `scopes` on top of what they granted (`include_granted_scopes=true`).
    /// Phase 3 calls this from Remote Config (`cloud-platform`) and Analytics
    /// (`analytics.readonly`).
    func requestAdditionalScopes(_ scopes: [String], for loginId: String) async throws -> GoogleSignInResult

    /// The stored login, or `nil`.
    func login(id loginId: String) -> GoogleLogin?

    /// The scopes of `scopes` the login has not granted, in order. Every scope
    /// is missing for an unknown login.
    func missingScopes(_ scopes: [String], for loginId: String) -> [String]

    /// Revokes the grant at Google (best effort) and deletes it from the device.
    func signOut(loginId: String) async
}

extension GoogleAuthServicing {
    /// Whether the login granted every scope of `scopes`.
    func hasGranted(_ scopes: [String], for loginId: String) -> Bool {
        missingScopes(scopes, for: loginId).isEmpty
    }
}

// MARK: - Implementation

/// Owns the Google logins: refresh token, scopes and e-mail in the Keychain
/// (`GoogleLoginStoring`), access tokens in memory only (plan G6).
///
/// Every dependency is injected (configuration, HTTP, web authentication,
/// storage, clock) so the flow is tested without Google.
@MainActor
final class GoogleAuthService: GoogleAuthServicing {

    static let shared = GoogleAuthService()

    /// Refresh this long before the access token actually expires.
    static let expiryLeeway: TimeInterval = 60

    private let configuration: GoogleOAuthConfiguration?
    private let tokenClient: GoogleOAuthTokenClient?
    private let store: GoogleLoginStoring
    private let authenticator: GoogleWebAuthenticating
    private let now: () -> Date

    private struct CachedAccessToken {
        let value: String
        let expiresAt: Date
    }

    private var accessTokens: [String: CachedAccessToken] = [:]
    /// One in-flight refresh per login, shared by concurrent callers.
    private var refreshTasks: [String: Task<String, Error>] = [:]

    init(
        configuration: GoogleOAuthConfiguration? = .fromBundle(),
        http: GoogleHTTPClient = URLSessionGoogleHTTPClient(),
        store: GoogleLoginStoring? = nil,
        authenticator: GoogleWebAuthenticating? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.tokenClient = configuration.map { GoogleOAuthTokenClient(configuration: $0, http: http) }
        self.store = store ?? GoogleLoginKeychainStore(keychain: KeychainStorable.shared)
        self.authenticator = authenticator ?? GoogleWebAuthenticator()
        self.now = now
    }

    var isConfigured: Bool { configuration != nil }

    // MARK: - Interactive authorization

    func signIn(scopes: [String]) async throws -> GoogleSignInResult {
        try await authorize(scopes: scopes, expectedLoginId: nil)
    }

    func requestAdditionalScopes(_ scopes: [String], for loginId: String) async throws -> GoogleSignInResult {
        guard store.load(loginId: loginId) != nil else { throw GoogleAuthError.loginNotFound }
        return try await authorize(scopes: scopes, expectedLoginId: loginId)
    }

    private func authorize(scopes: [String], expectedLoginId: String?) async throws -> GoogleSignInResult {
        guard let configuration, let tokenClient else { throw GoogleAuthError.notConfigured }

        let previous = expectedLoginId.flatMap { store.load(loginId: $0) }
        // The identity scopes are always asked, so every grant carries `sub`.
        let requested = Self.uniqued(GoogleOAuthScope.identity + scopes)
        let request = GoogleOAuthAuthorizationRequest.make(
            scopes: requested,
            includeGrantedScopes: expectedLoginId != nil,
            loginHint: previous?.email
        )
        Log.print.info("[GoogleAuth] Authorizing \(requested.count) scope(s), incremental: \(expectedLoginId != nil)")

        let callbackURL = try await authenticator.authenticate(
            url: request.url(configuration: configuration),
            callbackScheme: configuration.redirectScheme
        )

        let code: String
        do {
            code = try GoogleOAuthCallbackParser.authorizationCode(
                from: callbackURL,
                expectedState: request.state,
                configuration: configuration
            )
        } catch let error as GoogleOAuthCallbackError {
            Log.print.error("[GoogleAuth] Authorization redirect refused: \(String(describing: error), privacy: .public)")
            throw GoogleAuthError(callbackError: error)
        }

        let response = try await tokenClient.exchange(code: code, verifier: request.pkce.verifier)

        guard let claims = response.idToken.flatMap(GoogleIDTokenClaims.init(idToken:)) else {
            Log.print.error("[GoogleAuth] Code exchange returned no usable ID token")
            throw GoogleAuthError.missingIdentity
        }
        if let expectedLoginId, claims.subject != expectedLoginId {
            // Another Google account was picked in the chooser: its grant must
            // not replace this login's.
            Log.print.error("[GoogleAuth] Incremental authorization returned another Google account")
            throw GoogleAuthError.callback(.unexpectedRedirect)
        }

        let existing = previous ?? store.load(loginId: claims.subject)
        guard let refreshToken = response.refreshToken ?? existing?.refreshToken else {
            Log.print.error("[GoogleAuth] Code exchange returned no refresh token")
            throw GoogleAuthError.noRefreshToken
        }

        let granted = response.scope != nil ? response.grantedScopes : Set(requested)
        let issuedAt = now()
        let grant = GoogleLoginGrant(
            loginId: claims.subject,
            email: claims.email ?? existing?.email,
            refreshToken: refreshToken,
            grantedScopes: Array(granted),
            refreshTokenExpiresAt: response.refreshTokenExpiresIn.map { issuedAt.addingTimeInterval(TimeInterval($0)) },
            updatedAt: issuedAt
        )
        store.save(grant)
        cache(response, for: grant.loginId, issuedAt: issuedAt)

        let missing = GoogleOAuthScope.missing(requested, in: granted)
        Log.print.info("[GoogleAuth] Signed in (new login: \(existing == nil)); \(granted.count) scope(s) granted, \(missing.count) requested scope(s) not granted")
        return GoogleSignInResult(
            login: GoogleLogin(grant: grant),
            requestedScopes: requested,
            missingScopes: missing,
            isNewLogin: existing == nil
        )
    }

    // MARK: - Access tokens

    func accessToken(forLogin loginId: String) async throws -> String {
        if let cached = accessTokens[loginId], cached.expiresAt.timeIntervalSince(now()) > Self.expiryLeeway {
            return cached.value
        }
        if let task = refreshTasks[loginId] {
            return try await task.value
        }
        let task = Task { try await self.refresh(loginId: loginId) }
        refreshTasks[loginId] = task
        defer { refreshTasks[loginId] = nil }
        return try await task.value
    }

    /// Exchanges the stored refresh token for a new access token. A refresh
    /// response has no refresh token: the stored one is kept.
    private func refresh(loginId: String) async throws -> String {
        guard let tokenClient else { throw GoogleAuthError.notConfigured }
        guard var grant = store.load(loginId: loginId) else { throw GoogleAuthError.loginNotFound }

        let response: GoogleOAuthTokenResponse
        do {
            response = try await tokenClient.refresh(refreshToken: grant.refreshToken)
        } catch GoogleAuthError.invalidGrant {
            // Expired (7 days in Testing), revoked, or the password changed
            // (plan R5): only this login must sign in again.
            accessTokens[loginId] = nil
            Log.print.error("[GoogleAuth] Refresh token rejected (invalid_grant); the login must sign in again")
            throw GoogleAuthError.signInExpired(email: grant.email)
        } catch let error as GoogleAuthError {
            if case .http(let status, let summary) = error {
                Log.print.error("[GoogleAuth] Refresh failed: HTTP \(status, privacy: .public) \(summary?.logLine ?? "", privacy: .public)")
            }
            throw error
        }

        let issuedAt = now()
        if let refreshToken = response.refreshToken {
            grant.refreshToken = refreshToken
            grant.refreshTokenExpiresAt = response.refreshTokenExpiresIn.map { issuedAt.addingTimeInterval(TimeInterval($0)) }
        }
        if response.scope != nil {
            grant.grantedScopes = Array(response.grantedScopes)
        }
        grant.updatedAt = issuedAt
        store.save(grant)
        cache(response, for: loginId, issuedAt: issuedAt)
        Log.print.info("[GoogleAuth] Access token refreshed")
        return response.accessToken
    }

    private func cache(_ response: GoogleOAuthTokenResponse, for loginId: String, issuedAt: Date) {
        accessTokens[loginId] = CachedAccessToken(
            value: response.accessToken,
            expiresAt: issuedAt.addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }

    // MARK: - Logins and scopes

    func login(id loginId: String) -> GoogleLogin? {
        store.load(loginId: loginId).map(GoogleLogin.init(grant:))
    }

    func missingScopes(_ scopes: [String], for loginId: String) -> [String] {
        let granted = store.load(loginId: loginId)?.grantedScopeSet ?? []
        return GoogleOAuthScope.missing(scopes, in: granted)
    }

    // MARK: - Sign-out

    func signOut(loginId: String) async {
        let grant = store.load(loginId: loginId)
        accessTokens[loginId] = nil
        store.remove(loginId: loginId)
        guard let grant, let tokenClient else { return }
        do {
            try await tokenClient.revoke(token: grant.refreshToken)
            Log.print.info("[GoogleAuth] Google grant revoked")
        } catch {
            // Already deleted locally; the grant expires on Google's side or
            // can be removed in the user's Google account settings.
            Log.print.error("[GoogleAuth] Revoking the Google grant failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private static func uniqued(_ scopes: [String]) -> [String] {
        var seen = Set<String>()
        return scopes.filter { seen.insert($0).inserted }
    }
}
