import Foundation
import StackProtocols
@testable import StackConnect

// MARK: - HTTP

/// Scripted `GoogleHTTPClient`: answers each request with the first matching
/// handler and records every request sent.
final class MockGoogleHTTPClient: GoogleHTTPClient, @unchecked Sendable {

    typealias Handler = (URLRequest) -> GoogleHTTPResponse?

    private let lock = NSLock()
    private var handlers: [Handler] = []
    private var _requests: [URLRequest] = []
    /// Thrown instead of answering, when set.
    var error: Error?

    var requests: [URLRequest] { lock.withLock { _requests } }

    /// Answers requests whose URL path contains `path` (FIFO among matches
    /// when `once` is true).
    func respond(to path: String, status: Int = 200, json: Any, once: Bool = false) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        var used = false
        let handler: Handler = { request in
            guard request.url?.absoluteString.contains(path) == true else { return nil }
            if once {
                if used { return nil }
                used = true
            }
            return GoogleHTTPResponse(statusCode: status, data: data)
        }
        lock.withLock { handlers.append(handler) }
    }

    func send(_ request: URLRequest) async throws -> GoogleHTTPResponse {
        lock.withLock { _requests.append(request) }
        if let error { throw error }
        let current = lock.withLock { handlers }
        for handler in current {
            if let response = handler(request) { return response }
        }
        return GoogleHTTPResponse(statusCode: 404, data: Data())
    }

    func requests(to path: String) -> [URLRequest] {
        requests.filter { $0.url?.absoluteString.contains(path) == true }
    }

    /// The form fields of a POST body.
    static func formFields(of request: URLRequest) -> [String: String] {
        guard let body = request.httpBody, let text = String(data: body, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            fields[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return fields
    }
}

// MARK: - Web authentication

/// Returns a redirect built from the authorization URL it is handed, so the
/// `state` round-trips like Google's.
@MainActor
final class MockGoogleWebAuthenticator: GoogleWebAuthenticating {

    enum Outcome {
        /// Redirect with `code` and the request's own `state`.
        case code(String)
        /// Redirect with an `error` query item.
        case error(String)
        /// Redirect with a wrong `state`.
        case wrongState
        case throwing(Error)
    }

    var outcome: Outcome = .code("auth-code")
    private(set) var authorizationURLs: [URL] = []

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        authorizationURLs.append(url)
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value ?? ""
        let base = "\(callbackScheme):/oauth2redirect"
        switch outcome {
        case .code(let code):
            return URL(string: "\(base)?state=\(state)&code=\(code)")!
        case .error(let error):
            return URL(string: "\(base)?error=\(error)&state=\(state)")!
        case .wrongState:
            return URL(string: "\(base)?state=forged&code=abc")!
        case .throwing(let error):
            throw error
        }
    }
}

// MARK: - Fixtures

enum GoogleAuthFixtures {

    static let clientId = "1234-abc.apps.googleusercontent.com"
    static var configuration: GoogleOAuthConfiguration { GoogleOAuthConfiguration(clientId: clientId)! }

    /// An unsigned JWT carrying `sub` / `email` (the app never checks the signature).
    static func idToken(sub: String = "user-1", email: String? = "dev@example.com") -> String {
        var claims: [String: Any] = ["sub": sub, "aud": clientId]
        if let email { claims["email"] = email }
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncodedString()
        let payload = ((try? JSONSerialization.data(withJSONObject: claims)) ?? Data()).base64URLEncodedString()
        return "\(header).\(payload).signature"
    }

    static func tokenResponse(
        accessToken: String = "access-1",
        expiresIn: Int = 3600,
        refreshToken: String? = "refresh-1",
        scopes: [String]? = GoogleOAuthScope.signIn,
        idToken: String? = GoogleAuthFixtures.idToken()
    ) -> [String: Any] {
        var json: [String: Any] = ["access_token": accessToken, "expires_in": expiresIn, "token_type": "Bearer"]
        if let refreshToken { json["refresh_token"] = refreshToken }
        if let scopes { json["scope"] = scopes.joined(separator: " ") }
        if let idToken { json["id_token"] = idToken }
        return json
    }

    static func grant(loginId: String = "user-1", email: String? = "dev@example.com", scopes: [String] = GoogleOAuthScope.signIn) -> GoogleLoginGrant {
        GoogleLoginGrant(
            loginId: loginId,
            email: email,
            refreshToken: "stored-refresh",
            grantedScopes: scopes,
            refreshTokenExpiresAt: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

// MARK: - Service mock (ViewModel tests)

@MainActor
final class MockGoogleAuthService: GoogleAuthServicing {

    var isConfigured = true
    var signInResult: Result<GoogleSignInResult, Error> = .failure(GoogleAuthError.cancelled)
    var additionalScopesResult: Result<GoogleSignInResult, Error> = .failure(GoogleAuthError.cancelled)
    var logins: [String: GoogleLogin] = [:]
    var accessTokenResult: Result<String, Error> = .success("access-token")
    var reauthenticateResult: Result<GoogleSignInResult, Error> = .failure(GoogleAuthError.cancelled)

    private(set) var signInCalls: [[String]] = []
    private(set) var reauthenticateCalls: [String] = []
    private(set) var invalidatedLogins: [String] = []
    /// Becomes `accessTokenResult` once a token is invalidated (a refresh
    /// that succeeds, or fails with `invalid_grant`).
    var accessTokenAfterInvalidation: Result<String, Error>?
    private(set) var additionalScopesCalls: [(scopes: [String], loginId: String)] = []
    private(set) var signOutCalls: [String] = []

    func signIn(scopes: [String]) async throws -> GoogleSignInResult {
        signInCalls.append(scopes)
        let result = try signInResult.get()
        logins[result.login.loginId] = result.login
        return result
    }

    func requestAdditionalScopes(_ scopes: [String], for loginId: String) async throws -> GoogleSignInResult {
        additionalScopesCalls.append((scopes, loginId))
        let result = try additionalScopesResult.get()
        logins[result.login.loginId] = result.login
        return result
    }

    func reauthenticate(loginId: String) async throws -> GoogleSignInResult {
        reauthenticateCalls.append(loginId)
        let result = try reauthenticateResult.get()
        logins[result.login.loginId] = result.login
        return result
    }

    func invalidateAccessToken(forLogin loginId: String) async {
        invalidatedLogins.append(loginId)
        if let accessTokenAfterInvalidation {
            accessTokenResult = accessTokenAfterInvalidation
        }
    }

    func login(id loginId: String) -> GoogleLogin? { logins[loginId] }

    func missingScopes(_ scopes: [String], for loginId: String) -> [String] {
        GoogleOAuthScope.missing(scopes, in: logins[loginId]?.grantedScopes ?? [])
    }

    func signOut(loginId: String) async {
        signOutCalls.append(loginId)
        logins[loginId] = nil
    }

    func accessToken(forLogin loginId: String) async throws -> String {
        try accessTokenResult.get()
    }

    static func result(
        loginId: String = "user-1",
        email: String? = "dev@example.com",
        missing: [String] = [],
        isNewLogin: Bool = true
    ) -> GoogleSignInResult {
        GoogleSignInResult(
            login: GoogleLogin(
                loginId: loginId,
                email: email,
                grantedScopes: Set(GoogleOAuthScope.signIn).subtracting(missing)
            ),
            requestedScopes: GoogleOAuthScope.signIn,
            missingScopes: missing,
            isNewLogin: isNewLogin
        )
    }
}

// MARK: - Resource listing mock

final class MockGoogleResourceListing: GoogleResourceListing, @unchecked Sendable {

    var playAppsResult: Result<[GoogleAccessibleResource], Error> = .success([])
    var firebaseProjectsResult: Result<[GoogleAccessibleResource], Error> = .success([])

    func playApps(loginId: String) async throws -> [GoogleAccessibleResource] { try playAppsResult.get() }
    func firebaseProjects(loginId: String) async throws -> [GoogleAccessibleResource] { try firebaseProjectsResult.get() }
}

/// A fixed-token `GoogleAccessTokenProviding`.
struct StaticGoogleAccessTokenProvider: GoogleAccessTokenProviding {
    var token = "user-access-token"
    var error: GoogleAuthError?

    func accessToken(forLogin loginId: String) async throws -> String {
        if let error { throw error }
        return token
    }

    func invalidateAccessToken(forLogin loginId: String) async {}
}

// MARK: - Flags

extension FeatureFlags {
    /// `googleSignIn` OFF: Add Account shows the key-file form, as before the flag.
    static var googleSignInOff: FeatureFlags {
        let defaults = UserDefaults(suiteName: "StackConnectTests.googleSignInOff") ?? .standard
        defaults.set(false, forKey: FeatureFlag.googleSignIn.rawValue)
        return FeatureFlags(defaults: defaults)
    }
}
