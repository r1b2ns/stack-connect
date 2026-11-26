import Foundation
import StackCoreRust

/// The two ends of an Apple ID sign-in that the manual sign-in
/// (`AppleIdSignInViewModel`) and the automatic one
/// (`AppleSessionAutoReauthenticator`) share: building the core's sign-in
/// over the Apple ID's saved session, and keeping a finished one.
///
/// Never logs the password, the cookies or the session blob.
@MainActor
struct AppleSessionRenewal {

    /// Builds the core's sign-in: a fresh one, or one over the saved session
    /// (its trust cookie can spare the code when signing in again).
    typealias SignInFactory = (_ savedSession: Data?) throws -> any AppleIdSignInProtocol

    let sessionStore: AppleSessionKeychainStore
    let passwordStore: ApplePasswordKeychainStore
    let sessionStatus: AppleSessionStatusTracking
    let makeSignIn: SignInFactory

    init(
        keychain: KeyStorable,
        sessionStatus: AppleSessionStatusTracking,
        makeSignIn: SignInFactory? = nil
    ) {
        self.sessionStore = AppleSessionKeychainStore(keychain: keychain)
        self.passwordStore = ApplePasswordKeychainStore(keychain: keychain)
        self.sessionStatus = sessionStatus
        self.makeSignIn = makeSignIn ?? Self.coreSignIn
    }

    /// The core's real sign-in, audited while the `networkAudit` flag is ON
    /// (its SRP values and the two-factor code are masked for good).
    static func coreSignIn(_ savedSession: Data?) throws -> any AppleIdSignInProtocol {
        let auditSink = NetworkAuditCoreSinkFactory.make()
        if let savedSession {
            return try AppleIdSignIn.withSavedSession(blob: savedSession, auditSink: auditSink)
        }
        return try AppleIdSignIn(auditSink: auditSink)
    }

    /// A new core sign-in, over `appleId`'s saved session when one is given
    /// and stored (signing in again), otherwise a fresh one (Add Account).
    func makeFlow(reusingSessionOf appleId: String?) throws -> any AppleIdSignInProtocol {
        try makeSignIn(appleId.flatMap { sessionStore.load(accountId: $0) })
    }

    /// Ends `flow` and keeps its session in `appleId`'s shared Keychain item,
    /// applies "Save password on this device" to `password` (the one Apple
    /// just accepted), then marks the session as working again
    /// (`.signInStatusDidChange`).
    ///
    /// - `savesPassword` on: saves (or refreshes) `password` when given.
    /// - `savesPassword` off: removes any password saved earlier.
    func storeSession(
        of flow: any AppleIdSignInProtocol,
        appleId: String,
        password: String?,
        savesPassword: Bool
    ) async throws {
        let blob = try await flow.finish()
        sessionStore.save(accountId: appleId, blob: blob)
        storePassword(password, appleId: appleId, savesPassword: savesPassword)
        sessionStatus.markValid(appleId: appleId)
    }

    private func storePassword(_ password: String?, appleId: String, savesPassword: Bool) {
        if savesPassword {
            guard let password else { return }
            passwordStore.save(password, for: appleId)
            Log.print.info("[AppleIdSignIn] Saved the Apple ID password in the Keychain")
        } else if passwordStore.hasPassword(for: appleId) {
            passwordStore.deletePassword(for: appleId)
            Log.print.info("[AppleIdSignIn] Not saving the Apple ID password: removed the one saved earlier")
        }
    }

    /// `start`'s `InvalidCredentials` is a wrong Apple ID or password (the
    /// core maps a wrong code to it only from `submitCode`). The only failure
    /// that may remove the saved password.
    static func isWrongPassword(_ error: Error) -> Bool {
        failureKind(of: error) == .wrongPassword
    }

    /// A failure that says nothing about the password (see `FailureKind`):
    /// keep the saved one and retry with it.
    static func isTransient(_ error: Error) -> Bool {
        failureKind(of: error) == .transient
    }

    /// What a failed sign-in call means for the saved password. Shared by
    /// the manual sign-in and the automatic one, so both agree.
    enum FailureKind: Equatable {
        /// Apple refused the Apple ID or password (`InvalidCredentials`,
        /// HTTP 401 at `signin/init` or `signin/complete` in the core).
        case wrongPassword
        /// Apple or the network could not answer now: HTTP 429 (rate
        /// limited), any HTTP 5xx (`AppleUnavailable`), a network failure,
        /// a timeout or no connection. The password is kept and the error
        /// only shown; a retry uses it again.
        case transient
        /// Anything else (acknowledgement, decode, storage...): the password
        /// is kept too, but a retry is unlikely to help on its own.
        case other
    }

    static func failureKind(of error: Error) -> FailureKind {
        if let stackError = error as? StackError {
            switch stackError {
            case .InvalidCredentials:
                return .wrongPassword
            case .Http(let status, _):
                return isTransientHttpStatus(status) ? .transient : .other
            case .Network:
                return .transient
            default:
                return .other
            }
        }
        if OfflineError.isConnectivityFailure(error) || isConnectivityURLError(error) {
            return .transient
        }
        return .other
    }

    /// 429 (rate limited) and every 5xx (Apple's service unavailable).
    static func isTransientHttpStatus(_ status: UInt16) -> Bool {
        status == 429 || (500..<600).contains(status)
    }

    /// A Foundation network failure (offline, timeout, lost connection),
    /// should one ever reach the sign-in instead of the core's `.Network`.
    static func isConnectivityURLError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return connectivityURLErrorCodes.contains(urlError.code)
    }

    private static let connectivityURLErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
        .internationalRoamingOff, .dataNotAllowed, .callIsActive
    ]
}
