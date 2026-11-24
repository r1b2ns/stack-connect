import Foundation

// MARK: - HTTP layer (injectable)

struct GoogleHTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let data: Data

    var isSuccess: Bool { (200..<300).contains(statusCode) }
}

/// Sends one request. Injected so the token endpoint and the account picker's
/// API calls are tested without the network.
protocol GoogleHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> GoogleHTTPResponse
}

/// Ephemeral `URLSession`: no cookies or cache shared with other requests.
struct URLSessionGoogleHTTPClient: GoogleHTTPClient {

    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> GoogleHTTPResponse {
        let tagged = NetworkAuditRequestTag.tagged(
            request,
            origin: String(localized: "Sign in with Google", comment: "Network audit origin: the Google sign-in flow and its token refreshes.")
        )
        let (data, response) = try await session.data(for: tagged)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return GoogleHTTPResponse(statusCode: http.statusCode, data: data)
    }
}

// MARK: - Token response

/// The token endpoint's success body (code exchange and refresh).
struct GoogleOAuthTokenResponse: Decodable, Equatable, Sendable {
    let accessToken: String
    let expiresIn: Int
    /// Returned by a code exchange; a refresh usually returns none (keep the stored one).
    let refreshToken: String?
    /// Present while the consent screen is in Testing (7 days).
    let refreshTokenExpiresIn: Int?
    let scope: String?
    let idToken: String?

    var grantedScopes: Set<String> { GoogleOAuthScope.parse(scope) }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case scope
        case idToken = "id_token"
    }
}

// MARK: - Google error body

/// Both error shapes Google returns: API errors (`{"error": {"code", "status",
/// "message", "details": [{"reason"}]}}`) and OAuth endpoint errors
/// (`{"error": "invalid_grant", "error_description": "..."}`).
///
/// Only the machine-readable parts (status, reasons, OAuth error code) are
/// used to classify an error; the human `message` is never shown or logged.
struct GoogleAPIErrorSummary: Equatable, Sendable {
    var status: String?
    var reasons: [String] = []
    var oauthError: String?

    static func parse(_ data: Data) -> GoogleAPIErrorSummary? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        if let error = root["error"] as? [String: Any] {
            let details = error["details"] as? [[String: Any]] ?? []
            let legacy = error["errors"] as? [[String: Any]] ?? []
            return GoogleAPIErrorSummary(
                status: error["status"] as? String,
                reasons: (details + legacy).compactMap { $0["reason"] as? String }
            )
        }
        if let error = root["error"] as? String {
            return GoogleAPIErrorSummary(oauthError: error)
        }
        return nil
    }

    /// One line safe to log, e.g. `status=PERMISSION_DENIED reasons=SERVICE_DISABLED`.
    var logLine: String {
        var parts: [String] = []
        if let status { parts.append("status=\(status)") }
        if !reasons.isEmpty { parts.append("reasons=\(reasons.joined(separator: ","))") }
        if let oauthError { parts.append("error=\(oauthError)") }
        return parts.joined(separator: " ")
    }

    var isServiceDisabled: Bool { reasons.contains("SERVICE_DISABLED") }

    var isQuotaExceeded: Bool {
        status == "RESOURCE_EXHAUSTED" || reasons.contains { $0.hasPrefix("RATE_LIMIT") || $0 == "rateLimitExceeded" }
    }

    var isScopeInsufficient: Bool {
        reasons.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") || reasons.contains("insufficientPermissions")
    }
}

// MARK: - Token endpoint client

/// Code exchange, refresh and revoke against Google's token endpoints.
struct GoogleOAuthTokenClient: Sendable {

    let configuration: GoogleOAuthConfiguration
    let http: GoogleHTTPClient

    func exchange(code: String, verifier: String) async throws -> GoogleOAuthTokenResponse {
        try await sendTokenRequest(Self.exchangeRequest(code: code, verifier: verifier, configuration: configuration))
    }

    func refresh(refreshToken: String) async throws -> GoogleOAuthTokenResponse {
        try await sendTokenRequest(Self.refreshRequest(refreshToken: refreshToken, configuration: configuration))
    }

    /// Revokes the grant behind `token` (a refresh token also revokes its
    /// access tokens). A 400 `invalid_token` means it was already revoked,
    /// which is a success for the caller.
    func revoke(token: String) async throws {
        let response = try await http.send(Self.formRequest(url: GoogleOAuthEndpoint.revoke, fields: [("token", token)]))
        guard response.isSuccess else {
            let summary = GoogleAPIErrorSummary.parse(response.data)
            if response.statusCode == 400, summary?.oauthError == "invalid_token" { return }
            throw GoogleAuthError.http(statusCode: response.statusCode, summary: summary)
        }
    }

    private func sendTokenRequest(_ request: URLRequest) async throws -> GoogleOAuthTokenResponse {
        let response = try await send(request)
        guard response.isSuccess else {
            let summary = GoogleAPIErrorSummary.parse(response.data)
            if summary?.oauthError == "invalid_grant" {
                throw GoogleAuthError.invalidGrant
            }
            throw GoogleAuthError.http(statusCode: response.statusCode, summary: summary)
        }
        do {
            return try JSONDecoder().decode(GoogleOAuthTokenResponse.self, from: response.data)
        } catch {
            // Not logging `error`: a decoding error may echo the token body.
            throw GoogleAuthError.invalidTokenResponse
        }
    }

    private func send(_ request: URLRequest) async throws -> GoogleHTTPResponse {
        do {
            return try await http.send(request)
        } catch let error as URLError {
            throw GoogleAuthError.network(error.code)
        }
    }

    // MARK: Requests (pure, tested)

    static func exchangeRequest(code: String, verifier: String, configuration: GoogleOAuthConfiguration) -> URLRequest {
        formRequest(url: GoogleOAuthEndpoint.token, fields: [
            ("client_id", configuration.clientId),
            ("code", code),
            ("code_verifier", verifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", configuration.redirectURI)
        ])
    }

    static func refreshRequest(refreshToken: String, configuration: GoogleOAuthConfiguration) -> URLRequest {
        formRequest(url: GoogleOAuthEndpoint.token, fields: [
            ("client_id", configuration.clientId),
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken)
        ])
    }

    static func formRequest(url: URL, fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(fields).utf8)
        return request
    }

    static func formEncode(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        return fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }

    /// A GET with the user's bearer token.
    static func bearerRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
