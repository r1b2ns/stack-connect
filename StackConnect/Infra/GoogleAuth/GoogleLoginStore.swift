import Foundation

/// What survives a relaunch for one Google login (plan G6): the refresh token,
/// the granted scopes and the account e-mail. Access tokens stay in memory
/// (`GoogleAuthService`).
///
/// Security: `refreshToken` is a long-lived credential. It lives in the
/// Keychain only, is never logged, never shown and never exported (plan G7).
struct GoogleLoginGrant: Codable, Equatable, Sendable {
    /// Google's stable user ID (`sub`): the login's key on the device.
    let loginId: String
    var email: String?
    var refreshToken: String
    var grantedScopes: [String]
    /// Set while the consent screen is in Testing (7-day refresh tokens).
    var refreshTokenExpiresAt: Date?
    var updatedAt: Date

    var grantedScopeSet: Set<String> { Set(grantedScopes) }
}

/// Non-secret view of a login, safe to keep in UI state.
struct GoogleLogin: Equatable, Hashable, Sendable {
    let loginId: String
    let email: String?
    let grantedScopes: Set<String>

    init(loginId: String, email: String?, grantedScopes: Set<String>) {
        self.loginId = loginId
        self.email = email
        self.grantedScopes = grantedScopes
    }

    init(grant: GoogleLoginGrant) {
        self.init(loginId: grant.loginId, email: grant.email, grantedScopes: grant.grantedScopeSet)
    }

    /// The e-mail, or a neutral label when Google sent none.
    var displayName: String {
        email ?? String(localized: "Google account")
    }
}

/// Persists `GoogleLoginGrant`s, one Keychain item per login.
protocol GoogleLoginStoring {
    func load(loginId: String) -> GoogleLoginGrant?
    /// Whether the login's grant exists, telling a missing grant apart from a
    /// store that can't be read now (see `KeyPresence`).
    func presence(loginId: String) -> KeyPresence
    func save(_ grant: GoogleLoginGrant)
    func remove(loginId: String)
}

extension GoogleLoginStoring {
    /// Stores that can't fail to read know a grant is missing when `load` finds none.
    func presence(loginId: String) -> KeyPresence {
        load(loginId: loginId) == nil ? .missing : .present
    }
}

/// Keychain-backed through the app's `KeyStorable` abstraction.
struct GoogleLoginKeychainStore: GoogleLoginStoring {

    static func key(loginId: String) -> String { "googleLogin.\(loginId)" }

    private let keychain: KeyStorable

    init(keychain: KeyStorable) {
        self.keychain = keychain
    }

    func load(loginId: String) -> GoogleLoginGrant? {
        keychain.object(forKey: Self.key(loginId: loginId))
    }

    func presence(loginId: String) -> KeyPresence {
        keychain.presence(forKey: Self.key(loginId: loginId))
    }

    func save(_ grant: GoogleLoginGrant) {
        var normalized = grant
        normalized.grantedScopes = Array(Set(grant.grantedScopes)).sorted()
        keychain.setObject(normalized, forKey: Self.key(loginId: grant.loginId))
    }

    func remove(loginId: String) {
        keychain.removeObject(forKey: Self.key(loginId: loginId))
    }
}
