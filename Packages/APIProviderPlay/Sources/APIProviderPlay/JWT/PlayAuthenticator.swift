import Foundation

// MARK: - Errors

public enum PlayAuthError: Error, LocalizedError {
    case invalidPrivateKey
    case secKeyCreationFailed(Error)
    case invalidJWTPayload
    case signingFailed(Error?)
    case tokenExchangeFailed(statusCode: Int, body: String?)
    case invalidTokenResponse

    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "The RSA private key from the service account is invalid."
        case .secKeyCreationFailed(let error):
            return "Failed to load private key: \(error.localizedDescription)"
        case .invalidJWTPayload:
            return "Failed to encode JWT payload."
        case .signingFailed(let error):
            return "Failed to sign JWT: \(error?.localizedDescription ?? "unknown error")"
        case .tokenExchangeFailed(let statusCode, let body):
            return "Token exchange failed (\(statusCode)): \(body ?? "no body")"
        case .invalidTokenResponse:
            return "The token response could not be parsed."
        }
    }
}

// MARK: - OAuth Token Response

struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

// MARK: - Cached Token

struct CachedAccessToken {
    let token: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

// MARK: - PlayAuthenticator

final class PlayAuthenticator {

    private let configuration: PlayConfiguration
    private var cachedToken: CachedAccessToken?
    private let lock = NSLock()

    init(configuration: PlayConfiguration) {
        self.configuration = configuration
    }

    func accessToken() async throws -> String {
        lock.lock()
        if let cached = cachedToken, !cached.isExpired {
            lock.unlock()
            return cached.token
        }
        lock.unlock()

        let token = try await exchangeJWTForToken()

        lock.lock()
        cachedToken = token
        lock.unlock()

        return token.token
    }

    func adapt(_ urlRequest: URLRequest) async throws -> URLRequest {
        let token = try await accessToken()
        var request = urlRequest
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Private

    private func exchangeJWTForToken() async throws -> CachedAccessToken {
        let jwt = PlayJWT(configuration: configuration)
        let assertion = try jwt.signedAssertion()

        let tokenURL = URL(string: configuration.serviceAccount.tokenUri)!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = "grant_type=\(urlEncode("urn:ietf:params:oauth:grant-type:jwt-bearer"))&assertion=\(urlEncode(assertion))"
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlayAuthError.invalidTokenResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let body = String(data: data, encoding: .utf8)
            throw PlayAuthError.tokenExchangeFailed(statusCode: httpResponse.statusCode, body: body)
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

        return CachedAccessToken(
            token: tokenResponse.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )
    }

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}
