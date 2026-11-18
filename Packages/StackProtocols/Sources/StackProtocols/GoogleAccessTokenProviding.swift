import Foundation

/// Hands out a valid OAuth access token for one "Sign in with Google" login.
///
/// The seam between the providers that call Google APIs with the user's own
/// login (Firebase, and Google Play through the Rust core's
/// `AccessTokenProvider`) and the app's `GoogleAuthService`, which owns the
/// refresh tokens. A provider only ever needs this one call, so it never sees
/// a refresh token.
///
/// Implementations cache the access token in memory and refresh it when it is
/// about to expire. Errors are the implementation's own typed errors (an
/// expired or revoked login, offline, …); callers surface them unchanged.
///
/// Security: the returned value is a bearer credential. Never log it.
public protocol GoogleAccessTokenProviding: Sendable {
    /// A valid access token for the login `loginId`.
    func accessToken(forLogin loginId: String) async throws -> String
}
