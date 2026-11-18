import Foundation
import os
import StackCoreRust
import StackProtocols

/// The Rust core's `AccessTokenProvider` for a Google Play account added with
/// "Sign in with Google": hands the core the user's own access token from
/// `GoogleAccessTokenProviding` (`GoogleAuthService`), which owns the refresh
/// token, caches the access token and refreshes it. The core asks before every
/// request and never caches or sees a refresh token.
///
/// One instance per `GooglePlayAccountConnection`, bound to one login. The
/// core passes back the `accountId` the connection gave
/// `connectWithAccessToken`, which is this login's ID.
///
/// Failures follow the core's contract:
/// - offline / transient (no connection, a 5xx or a rate limit at Google's
///   token endpoint) → `StackError.Network`, so a Play screen keeps its cache
///   exactly as for a service account offline;
/// - anything else (an expired or revoked login, a missing login, an
///   unexpected answer) → `StackError.Auth`, whose message carries
///   `GoogleSignInCoreAuthMarker`. The core keeps an `Auth` message verbatim,
///   so `signInError(for:)` turns it back into the `GoogleAuthError`, and the
///   Play screens show Phase 2's "sign in again for <email>" copy.
///
/// Security: the token is a bearer credential. It is never logged.
final class GoogleSignInCoreTokenProvider: AccessTokenProvider {

    let loginId: String
    private let tokens: any GoogleAccessTokenProviding

    /// The last sign-in failure this provider turned into `StackError.Auth`,
    /// so the error coming back from the core maps to the exact
    /// `GoogleAuthError` (with the login's e-mail). Cleared on success.
    private let lastFailure = OSAllocatedUnfairLock<GoogleAuthError?>(initialState: nil)

    init(loginId: String, tokens: any GoogleAccessTokenProviding) {
        self.loginId = loginId
        self.tokens = tokens
    }

    // MARK: - AccessTokenProvider

    func accessToken(accountId: String) async throws -> String {
        if accountId != loginId {
            // A wiring bug: the core only ever passes the id it was built with.
            Log.print.fault("[GooglePlay] Token requested for another account id; using this connection's login")
        }
        do {
            let token = try await tokens.accessToken(forLogin: loginId)
            lastFailure.withLock { $0 = nil }
            return token
        } catch {
            let coreError = Self.coreError(for: error)
            if case .Auth = coreError {
                lastFailure.withLock { $0 = error as? GoogleAuthError }
            }
            Log.print.error("[GooglePlay] Google sign-in token unavailable: \(Self.logLabel(for: error), privacy: .public)")
            throw coreError
        }
    }

    // MARK: - Core error → app error

    /// The `GoogleAuthError` behind a core `StackError.Auth` that this
    /// provider raised, or `nil` for any other error (a Google Play 401/403,
    /// a 429, a network failure…), which the caller keeps unchanged.
    func signInError(for error: StackError) -> GoogleAuthError? {
        guard case .Auth(let message) = error,
              let kind = GoogleSignInCoreAuthMarker.kind(in: message) else {
            return nil
        }
        if let recorded = lastFailure.withLock({ $0 }) {
            return recorded
        }
        // A newer token request succeeded meanwhile: rebuild from the marker.
        switch kind {
        case .invalidGrant: return .signInExpired(email: nil)
        case .loginNotFound: return .loginNotFound
        case .notConfigured: return .notConfigured
        case .tokenError: return .invalidTokenResponse
        }
    }

    // MARK: - App error → core error

    /// Maps a `GoogleAccessTokenProviding` failure to the error the core
    /// expects (see the type's docs).
    static func coreError(for error: Error) -> StackError {
        switch error {
        case let authError as GoogleAuthError:
            return coreError(for: authError)
        case let urlError as URLError:
            return .Network(message: "Google sign-in token request failed: no connection to Google (URLError \(urlError.code.rawValue)).")
        case is CancellationError:
            return .Network(message: "Google sign-in token request was cancelled.")
        default:
            return GoogleSignInCoreAuthMarker.authError(.tokenError, detail: "the token request failed unexpectedly")
        }
    }

    private static func coreError(for error: GoogleAuthError) -> StackError {
        switch error {
        case .network(let code):
            return .Network(message: "Google sign-in token request failed: no connection to Google (URLError \(code.rawValue)).")
        case .http(let status, _) where status >= 500 || error.isQuotaExceeded:
            return .Network(message: "Google's token endpoint is temporarily unavailable (HTTP \(status)).")
        case .invalidGrant, .signInExpired:
            return GoogleSignInCoreAuthMarker.authError(.invalidGrant, detail: "the Google sign-in expired or was revoked; sign in with Google again")
        case .loginNotFound:
            return GoogleSignInCoreAuthMarker.authError(.loginNotFound, detail: "the Google sign-in is missing on this device; sign in with Google again")
        case .notConfigured:
            return GoogleSignInCoreAuthMarker.authError(.notConfigured, detail: "Sign in with Google isn't configured in this build")
        case .http(let status, _):
            return GoogleSignInCoreAuthMarker.authError(.tokenError, detail: "Google refused the token request (HTTP \(status))")
        case .cancelled, .webSessionFailedToStart, .accessDenied, .callback,
             .noRefreshToken, .missingIdentity, .invalidTokenResponse:
            return GoogleSignInCoreAuthMarker.authError(.tokenError, detail: "Google returned no usable access token")
        }
    }

    /// The failure's kind for the log: never a token, never Google's free text.
    private static func logLabel(for error: Error) -> String {
        switch error {
        case let authError as GoogleAuthError:
            switch authError {
            case .http(let status, _): return "GoogleAuthError.http(\(status))"
            case .network(let code): return "GoogleAuthError.network(\(code.rawValue))"
            case .signInExpired: return "GoogleAuthError.signInExpired"
            default: return "GoogleAuthError.\(authError)"
            }
        case let urlError as URLError:
            return "URLError(\(urlError.code.rawValue))"
        default:
            return String(reflecting: type(of: error))
        }
    }
}

/// The marker a `GoogleSignInCoreTokenProvider` puts in a `StackError.Auth`
/// message, e.g. `[stackconnect-google-sign-in:invalid_grant]`, so the app
/// recognizes its own sign-in failures when the core hands them back (the
/// core keeps an `Auth` message verbatim).
enum GoogleSignInCoreAuthMarker {

    enum Kind: String, CaseIterable {
        case invalidGrant = "invalid_grant"
        case loginNotFound = "login_not_found"
        case notConfigured = "not_configured"
        case tokenError = "token_error"
    }

    static let prefix = "[stackconnect-google-sign-in:"

    static func authError(_ kind: Kind, detail: String) -> StackError {
        .Auth(message: "Google sign-in \(prefix)\(kind.rawValue)]: \(detail).")
    }

    /// The marked kind in a core `Auth` message, or `nil` when unmarked.
    static func kind(in message: String) -> Kind? {
        guard let start = message.range(of: prefix),
              let end = message[start.upperBound...].firstIndex(of: "]") else {
            return nil
        }
        return Kind(rawValue: String(message[start.upperBound..<end]))
    }
}

/// `GoogleAccessTokenProviding` backed by the app's `GoogleAuthService.shared`,
/// resolved on the main actor at call time, so a connection can be built
/// anywhere (connections are created off the main actor too).
struct SharedGoogleAccessTokenProvider: GoogleAccessTokenProviding {
    func accessToken(forLogin loginId: String) async throws -> String {
        try await GoogleAuthService.shared.accessToken(forLogin: loginId)
    }
}
