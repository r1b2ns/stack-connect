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

    /// The core's real sign-in.
    static func coreSignIn(_ savedSession: Data?) throws -> any AppleIdSignInProtocol {
        if let savedSession {
            return try AppleIdSignIn.withSavedSession(blob: savedSession)
        }
        return try AppleIdSignIn()
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
    /// core maps a wrong code to it only from `submitCode`).
    static func isWrongPassword(_ error: Error) -> Bool {
        if case StackError.InvalidCredentials? = error as? StackError { return true }
        return false
    }
}
