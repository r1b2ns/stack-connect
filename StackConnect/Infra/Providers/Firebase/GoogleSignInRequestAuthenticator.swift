import Foundation
import APIProviderFirebase
import StackProtocols

/// Authenticates Firebase requests with a "Sign in with Google" login: the
/// user's own access token from `GoogleAccessTokenProviding`, refreshed by it
/// when needed. The refresh token never reaches the Firebase layer.
struct GoogleSignInRequestAuthenticator: RequestAuthenticating {

    let loginId: String
    let tokens: any GoogleAccessTokenProviding

    func adapt(_ urlRequest: URLRequest) async throws -> URLRequest {
        let token = try await tokens.accessToken(forLogin: loginId)
        var request = urlRequest
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Sign-in errors (an expired login, offline) reach the Firebase screens
/// unchanged, so they can say "sign in again" instead of a generic failure.
extension GoogleAuthError: RequestAuthenticationError {}
