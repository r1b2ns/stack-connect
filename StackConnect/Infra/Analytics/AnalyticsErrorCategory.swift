import Foundation
import APIProviderFirebase
import StackCoreRust
import StackProtocols

/// Why an account-onboarding step (`create_account`, `import_account`,
/// `reimport_account`) failed, sent as `error_category` next to
/// `result=failure`.
///
/// Answers "where do users give up?" without ever sending what went wrong in
/// their words: only these fixed raw values leave the device — never an error
/// message, a status text, a key, a file name or anything the user typed.
///
/// The set is deliberately small and stable (dashboards and GA4 custom
/// dimensions are built on the raw values): map new errors onto an existing
/// case before adding one, and never rename a raw value.
enum AnalyticsErrorCategory: String, CaseIterable, Sendable {
    /// The user's input was rejected locally, before any network call: empty
    /// name, invalid Play developer ID, empty or malformed key / JSON, a file
    /// of another provider than the section it was imported into.
    case validation = "validation"
    /// The same credentials are already stored under another account.
    case duplicate = "duplicate"
    /// The service refused the credentials (revoked or wrong key, HTTP 401,
    /// `invalid_grant`), or the core could not use them.
    case invalidCredentials = "invalid_credentials"
    /// Credentials accepted but not allowed (HTTP 403, missing role or Play
    /// Console permission, pending App Store agreements).
    case forbidden = "forbidden"
    /// Offline, or the request never reached the service.
    case network = "network"
    /// The service failed (HTTP 5xx) or answered something unreadable.
    case server = "server"
    /// Import only: the export file could not be decrypted with that password.
    case wrongPassword = "wrong_password"
    /// Import only: unreadable, not a `.scexport`, unsupported version, or a
    /// payload with missing / invalid fields or credentials.
    case invalidFile = "invalid_file"
    /// Everything was valid, but saving the account locally failed.
    case storage = "storage"
    /// "Sign in with Google" completed, but a scope the step needs was left
    /// unticked on the consent page (or the token lacks it).
    case scopeDenied = "scope_denied"
    /// Anything not classified above (e.g. a rate limit or an HTTP 404).
    case unknown = "unknown"

    /// `[error_category: rawValue]`, to merge into an `action` event.
    var parameters: [String: AnalyticsValue] {
        [AnalyticsParameterKey.errorCategory: .string(rawValue)]
    }
}

// MARK: - Mapping from real errors

extension AnalyticsErrorCategory {

    /// Classifies an error thrown while validating new credentials against the
    /// live service (Add Account: App Store Connect through the Rust core,
    /// Firebase through `APIProviderFirebase`, Google Play through the core).
    ///
    /// Only the error's *type and status code* are read, never its text.
    init(connectionError error: Error) {
        switch error {
        case is OfflineError:
            self = .network
        case let stackError as StackError:
            self = Self(stackError: stackError)
        case let firebaseError as APIProviderFirebase.Error:
            self = Self(firebaseError: firebaseError)
        case let authError as FirebaseAuthError:
            self = Self(firebaseAuthError: authError)
        case let writeError as GooglePlayReleaseWriteError:
            // Checked locally before any Play edit is opened.
            switch writeError {
            case .denied: self = .forbidden
            case .missingCredentials: self = .invalidCredentials
            }
        case let googleError as GoogleAuthError:
            self = Self(googleAuthError: googleError)
        case is GooglePlayServiceAccount.ParseError:
            // The offline format check of the pasted Play key.
            self = .validation
        case is DecodingError:
            // `FirebaseConfiguration(serviceAccountJSON:)` decoding the pasted
            // JSON; response decoding is wrapped in `.decodingError` instead.
            self = .validation
        case is URLError:
            self = .network
        default:
            self = .unknown
        }
    }

    /// Classifies a failed import (`AccountImporter`).
    init(importReason reason: AccountImportError.Reason) {
        switch reason {
        case .wrongPassword: self = .wrongPassword
        case .invalidFile: self = .invalidFile
        case .wrongProvider: self = .validation
        case .duplicate: self = .duplicate
        case .storage: self = .storage
        case .unknown: self = .unknown
        }
    }

    /// HTTP statuses that mean the same thing for every service.
    init(httpStatus status: Int) {
        switch status {
        case 401: self = .invalidCredentials
        case 403: self = .forbidden
        case 500..<600: self = .server
        default: self = .unknown
        }
    }

    // MARK: - Private

    private init(stackError: StackError) {
        switch stackError {
        case .InvalidCredentials, .Auth, .SessionExpired:
            // `.Auth` is the core's "the service refused this key / token"
            // (Apple 401, Google token exchange or access denied).
            // `.SessionExpired`: the Apple ID web session of a "Sign in with
            // Apple ID" account is no longer accepted (sign in again).
            self = .invalidCredentials
        case .PendingAgreements:
            self = .forbidden
        case .Network:
            self = .network
        case .Http(let status, _):
            self = Self(httpStatus: Int(status))
        case .Decode:
            self = .server
        case .Unsupported, .SubmissionNotRemovable, .ReleaseNotFound:
            self = .unknown
        }
    }

    private init(firebaseError: APIProviderFirebase.Error) {
        switch firebaseError {
        case .requestFailure(let status, _, _):
            self = Self(httpStatus: status)
        case .requestExecutorError(let underlying):
            self = underlying is URLError ? .network : .unknown
        case .decodingError, .unknownResponseType:
            self = .server
        case .requestGeneration:
            // Also wraps token-exchange failures, losing their cause: whether
            // it was the key or the network can't be told apart here.
            self = .unknown
        }
    }

    private init(googleAuthError: GoogleAuthError) {
        switch googleAuthError {
        case .accessDenied:
            // Blocked app, not a test user, Workspace policy, consent refused.
            self = .forbidden
        case .invalidGrant, .signInExpired, .loginNotFound, .differentAccount:
            self = .invalidCredentials
        case .network:
            self = .network
        case .noRefreshToken, .missingIdentity, .invalidTokenResponse:
            self = .server
        case .http(let status, _):
            if googleAuthError.isScopeInsufficient {
                self = .scopeDenied
            } else if googleAuthError.isServiceDisabled {
                // An API not enabled in StackConnect's own Cloud project.
                self = .server
            } else if googleAuthError.isQuotaExceeded {
                self = .unknown
            } else {
                self = Self(httpStatus: status)
            }
        case .notConfigured, .cancelled, .webSessionFailedToStart, .callback:
            self = .unknown
        }
    }

    private init(firebaseAuthError: FirebaseAuthError) {
        switch firebaseAuthError {
        case .invalidPrivateKey, .secKeyCreationFailed, .invalidJWTPayload:
            // The pasted service account JSON has an unusable key.
            self = .validation
        case .tokenExchangeFailed(let status, _):
            // Google answers 400 `invalid_grant` for a deleted / revoked key.
            self = status == 400 ? .invalidCredentials : Self(httpStatus: status)
        case .invalidTokenResponse:
            self = .server
        case .signingFailed:
            self = .unknown
        }
    }
}
