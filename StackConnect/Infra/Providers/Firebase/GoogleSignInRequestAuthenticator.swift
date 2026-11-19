import Foundation
import APIProviderFirebase
import StackProtocols

/// Authenticates Firebase requests with a "Sign in with Google" login: the
/// user's own access token from `GoogleAccessTokenProviding`, refreshed by it
/// when needed. The refresh token never reaches the Firebase layer.
///
/// An HTTP 401 means Google rejected the cached access token before it
/// expired (revoked, password changed): `APIProviderFirebase` asks once to
/// retry, the token is dropped and the request goes out again with a refreshed
/// one. If the refresh itself fails with `invalid_grant`, the screen gets
/// `GoogleAuthError.signInExpired` and offers "Sign in again".
struct GoogleSignInRequestAuthenticator: RequestReauthenticating {

    let loginId: String
    let tokens: any GoogleAccessTokenProviding

    func adapt(_ urlRequest: URLRequest) async throws -> URLRequest {
        let token = try await tokens.accessToken(forLogin: loginId)
        var request = urlRequest
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func shouldRetryAfterUnauthorized() async -> Bool {
        await tokens.invalidateAccessToken(forLogin: loginId)
        Log.print.info("[Firebase] Google rejected the sign-in access token (HTTP 401); retrying once with a fresh one")
        return true
    }
}

/// Sign-in errors (an expired login, offline) reach the Firebase screens
/// unchanged, so they can say "sign in again" instead of a generic failure.
extension GoogleAuthError: RequestAuthenticationError {}
