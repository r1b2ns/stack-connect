import Foundation

/// Why a "Sign in with Google" step failed (plan Phase 2, risks R3–R5).
///
/// `errorDescription` is user-facing copy. No case carries a token, an
/// authorization code or Google's free-text error message.
enum GoogleAuthError: LocalizedError, Equatable, Sendable {
    /// The build has no OAuth client ID (`GOOGLE_OAUTH_CLIENT_ID`).
    case notConfigured
    /// The user closed the browser sheet.
    case cancelled
    case webSessionFailedToStart
    /// Google refused the authorization: the app is blocked, the account is not
    /// a test user while the consent screen is in Testing, a Workspace admin
    /// blocks third-party apps, or the user pressed Cancel on the consent page.
    case accessDenied
    /// Any other redirect problem (state mismatch, missing code, other error).
    case callback(GoogleOAuthCallbackError)
    /// The refresh token was expired or revoked (`invalid_grant`, plan R5).
    case invalidGrant
    /// `invalidGrant` for a known login: only that login must sign in again.
    case signInExpired(email: String?)
    /// No stored grant for the login an account refers to.
    case loginNotFound
    /// The code exchange returned no refresh token (nothing to keep).
    case noRefreshToken
    /// The code exchange returned no usable ID token (`sub` claim).
    case missingIdentity
    /// Google answered with an error status. Classified by `summary`.
    case http(statusCode: Int, summary: GoogleAPIErrorSummary?)
    /// The request never reached Google.
    case network(URLError.Code)
    case invalidTokenResponse

    // MARK: - Classification

    /// The API Google needs is disabled in StackConnect's Cloud project (the
    /// OAuth client's project is the quota consumer, plan section 1).
    var isServiceDisabled: Bool {
        if case .http(_, let summary) = self { return summary?.isServiceDisabled == true }
        return false
    }

    /// A rate limit of StackConnect's Cloud project (plan R1).
    var isQuotaExceeded: Bool {
        if case .http(let status, let summary) = self { return status == 429 || summary?.isQuotaExceeded == true }
        return false
    }

    /// The token lacks a scope (an unticked checkbox, or a Phase 3 scope).
    var isScopeInsufficient: Bool {
        if case .http(_, let summary) = self { return summary?.isScopeInsufficient == true }
        return false
    }

    /// The login must sign in again.
    var requiresSignIn: Bool {
        switch self {
        case .invalidGrant, .signInExpired, .loginNotFound: return true
        default: return false
        }
    }

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "Sign in with Google isn't available in this build.")
        case .cancelled:
            return String(localized: "Sign in with Google was cancelled.")
        case .webSessionFailedToStart:
            return String(localized: "Couldn't open the Google sign-in page. Try again.")
        case .accessDenied:
            return String(localized: "Google blocked the sign-in. While StackConnect's Google access is in testing, only invited accounts can sign in, and some organizations block third-party apps. You can still add the account with a service account JSON.")
        case .callback:
            return String(localized: "Google sign-in didn't complete. Try again.")
        case .invalidGrant:
            return String(localized: "Your Google sign-in expired or was revoked. Sign in with Google again.")
        case .signInExpired(let email):
            if let email {
                return String(localized: "The Google sign-in for \(email) expired or was revoked. Add the account again with Sign in with Google, using the same Google account, to restore access.")
            }
            return String(localized: "Your Google sign-in expired or was revoked. Add the account again with Sign in with Google, using the same Google account, to restore access.")
        case .loginNotFound:
            return String(localized: "This account's Google sign-in is missing on this device. Add the account again with Sign in with Google.")
        case .noRefreshToken, .missingIdentity, .invalidTokenResponse:
            return String(localized: "Google returned an unexpected answer. Try signing in again.")
        case .http(let status, _):
            if isScopeInsufficient {
                return String(localized: "This needs a Google permission you didn't grant. Sign in with Google again and allow it.")
            }
            if status == 401 {
                return String(localized: "Your Google sign-in expired or was revoked. Sign in with Google again.")
            }
            if status == 403, !isServiceDisabled, !isQuotaExceeded {
                return String(localized: "Your Google account doesn't have access to this.")
            }
            // SERVICE_DISABLED on StackConnect's project, quota, 5xx: nothing
            // the user can fix. Logged by the caller, generic copy here.
            return String(localized: "Google couldn't complete the request right now. Try again later.")
        case .network:
            return String(localized: "No connection to Google. Check your internet connection and try again.")
        }
    }
}

extension GoogleAuthError {

    /// Maps a web authentication callback problem: `access_denied` (and the
    /// policy errors Google sends for blocked apps) become `accessDenied`.
    init(callbackError: GoogleOAuthCallbackError) {
        switch callbackError {
        case .authorizationFailed(let code) where Self.accessDeniedCodes.contains(code):
            self = .accessDenied
        default:
            self = .callback(callbackError)
        }
    }

    static let accessDeniedCodes: Set<String> = ["access_denied", "admin_policy_enforced", "org_internal", "disallowed_useragent"]
}
