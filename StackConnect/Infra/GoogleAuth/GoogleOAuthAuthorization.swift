import CryptoKit
import Foundation

// MARK: - PKCE

/// RFC 7636 PKCE pair: `challenge = base64url(SHA256(verifier))`, no padding.
struct GoogleOAuthPKCE: Equatable, Sendable {

    static let method = "S256"

    let verifier: String
    let challenge: String

    init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
    }

    /// 32 random bytes: a 43-character verifier (the RFC 7636 minimum).
    static func generate() -> GoogleOAuthPKCE {
        GoogleOAuthPKCE(verifier: randomURLSafeString(byteCount: 32))
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    /// `SystemRandomNumberGenerator` is cryptographically secure on Apple platforms.
    static func randomURLSafeString(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    /// Base64url without padding (RFC 4648 §5).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes base64url with or without padding.
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}

// MARK: - Authorization request

/// One interactive authorization: the URL opened in the system browser sheet
/// and the values needed to check its redirect and exchange its code.
struct GoogleOAuthAuthorizationRequest: Equatable, Sendable {

    let scopes: [String]
    let pkce: GoogleOAuthPKCE
    let state: String
    /// `true` for an incremental request: Google keeps the scopes already granted.
    let includeGrantedScopes: Bool
    /// Pre-selects a Google account in the account chooser (re-sign-in or an
    /// incremental request for a known login).
    let loginHint: String?

    static func make(
        scopes: [String],
        includeGrantedScopes: Bool = false,
        loginHint: String? = nil
    ) -> GoogleOAuthAuthorizationRequest {
        GoogleOAuthAuthorizationRequest(
            scopes: scopes,
            pkce: .generate(),
            state: GoogleOAuthPKCE.randomURLSafeString(byteCount: 16),
            includeGrantedScopes: includeGrantedScopes,
            loginHint: loginHint
        )
    }

    func url(configuration: GoogleOAuthConfiguration) -> URL {
        var items = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: GoogleOAuthPKCE.method),
            // iOS clients get a refresh token with every code exchange (spike,
            // plan section 1): no `access_type` / `prompt` needed.
            URLQueryItem(name: "state", value: state)
        ]
        if includeGrantedScopes {
            items.append(URLQueryItem(name: "include_granted_scopes", value: "true"))
        }
        if let loginHint, !loginHint.isEmpty {
            items.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        var components = URLComponents(url: GoogleOAuthEndpoint.authorization, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        // `+` is legal in a query but Google reads it as a space: encode it.
        let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encodedQuery
        // The base URL is constant and the items are plain strings.
        return components?.url ?? GoogleOAuthEndpoint.authorization
    }
}

// MARK: - Callback

/// Why a redirect carries no usable authorization code.
enum GoogleOAuthCallbackError: Error, Equatable, Sendable {
    case unexpectedRedirect
    /// Google's `error` query item, e.g. `access_denied`.
    case authorizationFailed(String)
    case stateMismatch
    case missingCode
}

enum GoogleOAuthCallbackParser {

    /// The authorization code of a redirect. The `error` item is checked first
    /// (nothing from an error redirect is used), then `state`, then `code`.
    static func authorizationCode(
        from url: URL,
        expectedState: String,
        configuration: GoogleOAuthConfiguration
    ) throws -> String {
        guard url.scheme?.lowercased() == configuration.redirectScheme.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleOAuthCallbackError.unexpectedRedirect
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let error = value("error") {
            throw GoogleOAuthCallbackError.authorizationFailed(error)
        }
        guard value("state") == expectedState else {
            throw GoogleOAuthCallbackError.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw GoogleOAuthCallbackError.missingCode
        }
        return code
    }
}

// MARK: - ID token

/// The claims of the ID token that identify a login. The token comes straight
/// from Google's token endpoint over TLS, so its signature is not checked
/// (OpenID Connect Core §3.1.3.7).
struct GoogleIDTokenClaims: Equatable, Sendable {
    /// Google's stable user ID: the login's identity on the device.
    let subject: String
    let email: String?

    /// `nil` when `idToken` is not a JWT with a `sub` claim.
    init?(idToken: String) {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let data = Data(base64URLEncoded: String(parts[1])),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let subject = json["sub"] as? String, !subject.isEmpty else {
            return nil
        }
        self.subject = subject
        self.email = json["email"] as? String
    }
}
