import Foundation
import APIProviderFirebase
import StackProtocols

// MARK: - Prompt (UI state)

/// What a Firebase screen of a "Sign in with Google" account shows instead of
/// its content when the Google login can't serve it: an extra permission to
/// grant (plan G3, Phase 3), or a sign-in to redo (plan R5). Rendered by
/// `StackGoogleAccessPromptView`.
struct GoogleAccessPrompt: Equatable, Sendable {

    enum Reason: Equatable, Sendable {
        /// The login hasn't granted the screen's sensitive scope (or Google
        /// says the token lacks it although it was recorded as granted).
        case permissionNeeded(GoogleSensitiveScopeFeature)
        /// The login's grant expired, was revoked or is missing on the device.
        case signInRequired
    }

    var reason: Reason
    /// The Google account the StackConnect account uses, when known.
    var email: String?
    /// The primary action is running (Google's page is open).
    var isWorking = false
    /// Why the last attempt didn't resolve it (an unticked checkbox, another
    /// Google account, an error). `nil` after a cancel: closing Google's sheet
    /// is not an error.
    var feedback: String?
}

// MARK: - Recovery

/// The shared "Grant access" / "Sign in again" logic of the Firebase screens
/// (Project list, App list, Remote Config, Messaging, Analytics), so each
/// ViewModel only decides when to ask and reloads when it is resolved.
///
/// Service-account accounts never get a prompt: every method is a no-op for
/// them (`loginId == nil`).
@MainActor
final class GoogleAccessRecovery {

    /// The account's Google login, `nil` for a service-account account.
    let loginId: String?

    private let auth: any GoogleAuthServicing
    private let analytics: AnalyticsTracking
    private let screen: AnalyticsScreen

    init(
        account: AccountModel,
        keychain: KeyStorable,
        auth: (any GoogleAuthServicing)? = nil,
        analytics: AnalyticsTracking,
        screen: AnalyticsScreen
    ) {
        self.loginId = account.providerType == .firebase
            ? GoogleLoginReferences.loginId(of: account, keychain: keychain)
            : nil
        self.auth = auth ?? GoogleAuthService.shared
        self.analytics = analytics
        self.screen = screen
    }

    // MARK: - When to prompt

    /// The prompt to show instead of calling the API: the login hasn't
    /// granted `feature`'s scope. `nil` for a service account, or when granted.
    func promptBeforeLoading(_ feature: GoogleSensitiveScopeFeature) -> GoogleAccessPrompt? {
        guard let loginId, !auth.hasGranted([feature.scope], for: loginId) else { return nil }
        Log.print.info("[GoogleAccess] \(feature.rawValue, privacy: .public) needs a scope the Google login hasn't granted; asking first")
        return makePrompt(.permissionNeeded(feature))
    }

    /// The prompt for a failed Firebase call, or `nil` when `error` isn't
    /// about the Google login (the screen shows its usual error then):
    /// - an expired, revoked or missing login → "Sign in again";
    /// - `feature`'s scope recorded as granted but Google answering 403
    ///   `ACCESS_TOKEN_SCOPE_INSUFFICIENT` (revoked elsewhere) → "Grant access".
    func prompt(for error: Error, feature: GoogleSensitiveScopeFeature? = nil) -> GoogleAccessPrompt? {
        guard loginId != nil else { return nil }
        if let authError = error as? GoogleAuthError, authError.requiresSignIn {
            Log.print.notice("[GoogleAccess] The Google login must sign in again")
            return makePrompt(.signInRequired)
        }
        if let feature, Self.isScopeInsufficient(error) {
            Log.print.notice("[GoogleAccess] Google says the token lacks the \(feature.rawValue, privacy: .public) scope")
            return makePrompt(.permissionNeeded(feature))
        }
        return nil
    }

    /// The copy for Google's 403 `SERVICE_DISABLED` on a Google sign-in
    /// account, or `nil` for any other error or a service account.
    ///
    /// With the user's own login, the quota (consumer) project is
    /// StackConnect's OAuth client project, not the user's Firebase project:
    /// the user can't enable the API, and Google's activation link points to
    /// StackConnect's project. So no "Enable API" link and no "enable it for
    /// this project" copy: a generic "temporarily unavailable" line, and the
    /// error is logged here (status, reason, service and consumer only).
    func unavailableMessage(for error: Error) -> String? {
        guard loginId != nil,
              case .requestFailure(let status, let response?, _)? = error as? APIProviderFirebase.Error,
              response.isServiceDisabled else { return nil }
        let metadata = response.error?.details?.compactMap(\.metadata).first
        Log.print.error("[GoogleAccess] SERVICE_DISABLED in StackConnect's OAuth client project: HTTP \(status, privacy: .public) status=\(response.error?.status ?? "-", privacy: .public) reason=SERVICE_DISABLED service=\(metadata?.service ?? "-", privacy: .public) consumer=\(metadata?.consumer ?? "-", privacy: .public)")
        return Self.unavailableMessage
    }

    static var unavailableMessage: String {
        String(localized: "This feature is temporarily unavailable. Try again later.",
               comment: "Firebase screen of an account added with Sign in with Google, when a Google API is disabled on StackConnect's side (nothing the user can fix).")
    }

    /// Whether a sign-in failure must be shown as "Sign in again" (for the
    /// screens that only show a toast for a failed write).
    func requiresSignIn(_ error: Error) -> Bool {
        guard loginId != nil, let authError = error as? GoogleAuthError else { return false }
        return authError.requiresSignIn
    }

    // MARK: - Primary action

    /// Runs the prompt's primary action ("Grant access" or "Sign in again").
    /// `update` receives each intermediate state (working, feedback, a switch
    /// to "Sign in again"). - Returns: `true` when the screen should reload.
    func resolve(_ prompt: GoogleAccessPrompt, update: (GoogleAccessPrompt) -> Void) async -> Bool {
        guard let loginId else { return false }
        var working = prompt
        working.isWorking = true
        working.feedback = nil
        update(working)

        switch prompt.reason {
        case .permissionNeeded(let feature):
            return await grant(feature, loginId: loginId, prompt: prompt, update: update)
        case .signInRequired:
            return await signInAgain(loginId: loginId, prompt: prompt, update: update)
        }
    }

    // MARK: - Private

    private func grant(
        _ feature: GoogleSensitiveScopeFeature,
        loginId: String,
        prompt: GoogleAccessPrompt,
        update: (GoogleAccessPrompt) -> Void
    ) async -> Bool {
        analytics.track(.buttonTap(.grantGoogleAccess, on: screen))
        let kind = [AnalyticsParameterKey.kind: AnalyticsValue.string(feature.analyticsValue)]
        analytics.track(.action(.googleScopeGrantStarted, on: screen, parameters: kind))

        var next = prompt
        next.isWorking = false
        do {
            _ = try await auth.requestAdditionalScopes([feature.scope], for: loginId)
            guard auth.hasGranted([feature.scope], for: loginId) else {
                // The consent page was completed with the checkbox unticked (R4).
                Log.print.notice("[GoogleAccess] \(feature.rawValue, privacy: .public) scope still not granted")
                analytics.track(.action(.googleScopeGrant, on: screen, result: .failure,
                                        parameters: kind.merging(AnalyticsErrorCategory.scopeDenied.parameters) { _, new in new }))
                next.feedback = String(localized: "Google didn't grant the permission: its checkbox was left unticked. Tap Grant Access and keep it ticked.")
                update(next)
                return false
            }
            Log.print.info("[GoogleAccess] \(feature.rawValue, privacy: .public) scope granted")
            analytics.track(.action(.googleScopeGrant, on: screen, result: .success, parameters: kind))
            return true
        } catch {
            track(.googleScopeGrant, error: error, parameters: kind)
            if let authError = error as? GoogleAuthError, authError.requiresSignIn {
                // The grant expired meanwhile: offer "Sign in again" instead.
                next.reason = .signInRequired
                next.email = auth.login(id: loginId)?.email ?? prompt.email
            } else {
                next.feedback = feedback(for: error)
            }
            update(next)
            return false
        }
    }

    private func signInAgain(loginId: String, prompt: GoogleAccessPrompt, update: (GoogleAccessPrompt) -> Void) async -> Bool {
        analytics.track(.buttonTap(.signInAgain, on: screen))
        let kind = [AnalyticsParameterKey.kind: AnalyticsValue.string(ProviderType.firebase.rawValue)]
        analytics.track(.action(.googleSignInStarted, on: screen, parameters: kind))

        var next = prompt
        next.isWorking = false
        do {
            let result = try await auth.reauthenticate(loginId: loginId)
            Log.print.info("[GoogleAccess] Signed in again with the same Google account")
            analytics.track(.action(.googleSignIn, on: screen, result: .success, parameters: kind.merging([
                AnalyticsParameterKey.missingScopeCount: .int(result.missingScopes.count)
            ]) { _, new in new }))
            return true
        } catch {
            track(.googleSignIn, error: error, parameters: kind)
            next.feedback = feedback(for: error)
            update(next)
            return false
        }
    }

    /// `cancelled` for a closed sheet, `failure` with the error category otherwise.
    private func track(_ action: AnalyticsAction, error: Error, parameters: [String: AnalyticsValue]) {
        if case GoogleAuthError.cancelled = error {
            Log.print.info("[GoogleAccess] Google's page was closed")
            analytics.track(.action(action, on: screen, result: .cancelled, parameters: parameters))
            return
        }
        Log.print.error("[GoogleAccess] Google authorization failed: \(error.localizedDescription, privacy: .public)")
        analytics.track(.action(action, on: screen, result: .failure,
                                parameters: parameters.merging(AnalyticsErrorCategory.parameters(for: error)) { _, new in new }))
    }

    /// `nil` for a cancel (no error banner), Google's own friendly copy for a
    /// sign-in error, a generic line for anything else.
    private func feedback(for error: Error) -> String? {
        switch error {
        case GoogleAuthError.cancelled:
            return nil
        case let authError as GoogleAuthError:
            return authError.errorDescription
        default:
            return String(localized: "Google couldn't complete the request right now. Try again later.")
        }
    }

    private func makePrompt(_ reason: GoogleAccessPrompt.Reason) -> GoogleAccessPrompt {
        GoogleAccessPrompt(reason: reason, email: loginId.flatMap { auth.login(id: $0)?.email })
    }

    /// Google's `SERVICE_DISABLED` on a Firebase call.
    static func isServiceDisabled(_ error: Error) -> Bool {
        guard case .requestFailure(_, let response, _)? = error as? APIProviderFirebase.Error else { return false }
        return response?.isServiceDisabled == true
    }

    /// Google's 403 `ACCESS_TOKEN_SCOPE_INSUFFICIENT` on a Firebase call.
    static func isScopeInsufficient(_ error: Error) -> Bool {
        guard case .requestFailure(let status, let response, _)? = error as? APIProviderFirebase.Error else { return false }
        return status == 403 && response?.isScopeInsufficient == true
    }
}
