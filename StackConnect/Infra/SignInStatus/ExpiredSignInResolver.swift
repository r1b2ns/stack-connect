import Foundation

extension Notification.Name {
    /// Posted on the main thread whenever an account's sign-in becomes expired
    /// or works again: an Apple ID session (`AppleSessionStatusStore`) or a
    /// Google login (`GoogleLoginStatusStore`). No `object`, no `userInfo`:
    /// observers re-read the stores.
    static let signInStatusDidChange = Notification.Name("StackConnect.signInStatusDidChange")
}

extension NotificationCenter {
    /// Posts `.signInStatusDidChange` on the main thread.
    func postSignInStatusDidChange() {
        if Thread.isMainThread {
            post(name: .signInStatusDidChange, object: nil)
        } else {
            DispatchQueue.main.async { [self] in post(name: .signInStatusDidChange, object: nil) }
        }
    }
}

// MARK: - Model

/// One personal sign-in that stopped working, with every account that uses
/// it. Signing in again once restores all of them (an Apple ID session serves
/// every team account of that Apple ID; a Google login every account added
/// with that Google user).
struct ExpiredSignIn: Identifiable, Equatable, Sendable {

    enum Provider: Equatable, Hashable, Sendable {
        /// An expired Apple ID web session (normalized Apple ID).
        case appleId(String)
        /// An expired, revoked or missing Google login (Google's `sub`).
        case google(loginId: String)
    }

    struct Account: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let providerType: ProviderType
    }

    let provider: Provider
    /// The login shown to the user: the Apple ID, or the Google e-mail when known.
    let login: String?
    let accounts: [Account]

    var id: String { Self.id(of: provider) }

    /// The `id` of the expired sign-in of `provider`.
    static func id(of provider: Provider) -> String {
        switch provider {
        case .appleId(let appleId): return "apple:\(appleId)"
        case .google(let loginId): return "google:\(loginId)"
        }
    }
}

// MARK: - Resolver

/// Lists the accounts whose personal sign-in has expired, grouped by sign-in.
@MainActor
protocol ExpiredSignInResolving {
    func expiredSignIns(in accounts: [AccountModel]) -> [ExpiredSignIn]
}

/// How the app knows a sign-in expired, per provider:
/// - Apple ID session: App Store Connect refused it
///   (`AppleSessionStatusTracking`, set by `AppleAccountConnection`).
/// - Google login: Google answered `invalid_grant` on a refresh
///   (`GoogleLoginStatusTracking`, set by `GoogleAuthService`), the grant is
///   missing on the device (not merely unreadable while it is locked), or its refresh token's own expiry
///   (`refreshTokenExpiresAt`, 7 days while the consent screen is in
///   Testing) has passed.
///
/// API key and service account accounts never expire this way.
@MainActor
struct ExpiredSignInResolver: ExpiredSignInResolving {

    private let keychain: KeyStorable
    private let appleStatus: AppleSessionStatusTracking
    private let googleStatus: GoogleLoginStatusTracking
    private let googleLogins: GoogleLoginStoring
    private let now: () -> Date

    init(
        keychain: KeyStorable,
        appleStatus: AppleSessionStatusTracking = AppleSessionStatusStore.shared,
        googleStatus: GoogleLoginStatusTracking = GoogleLoginStatusStore.shared,
        googleLogins: GoogleLoginStoring? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.keychain = keychain
        self.appleStatus = appleStatus
        self.googleStatus = googleStatus
        self.googleLogins = googleLogins ?? GoogleLoginKeychainStore(keychain: keychain)
        self.now = now
    }

    func expiredSignIns(in accounts: [AccountModel]) -> [ExpiredSignIn] {
        var order: [ExpiredSignIn.Provider] = []
        var logins: [ExpiredSignIn.Provider: String?] = [:]
        var grouped: [ExpiredSignIn.Provider: [ExpiredSignIn.Account]] = [:]

        let sorted = accounts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for account in sorted {
            guard let (provider, login) = expiredProvider(of: account) else { continue }
            if grouped[provider] == nil {
                order.append(provider)
                logins[provider] = login
            }
            grouped[provider, default: []].append(
                ExpiredSignIn.Account(id: account.id, name: account.name, providerType: account.providerType)
            )
        }

        return order.map { provider in
            ExpiredSignIn(provider: provider, login: logins[provider] ?? nil, accounts: grouped[provider] ?? [])
        }
    }

    private func expiredProvider(of account: AccountModel) -> (ExpiredSignIn.Provider, String?)? {
        if let reference = AppleSessionReferences.reference(of: account, keychain: keychain) {
            guard appleStatus.isExpired(appleId: reference.appleId) else { return nil }
            return (.appleId(reference.appleId), reference.appleId)
        }
        guard account.authMethod == .googleSignIn,
              let loginId = GoogleLoginReferences.loginId(of: account, keychain: keychain) else { return nil }
        let grant = googleLogins.load(loginId: loginId)
        // A grant that can't be read now (device locked, prewarm, background
        // task) is not a missing one: only Google's own answer or a definite
        // "not found" makes the login expired.
        let isGrantMissing = grant == nil && googleLogins.presence(loginId: loginId) != .unavailable
        let isExpired = googleStatus.isExpired(loginId: loginId)
            || isGrantMissing
            || (grant?.refreshTokenExpiresAt.map { $0 <= now() } ?? false)
        guard isExpired else { return nil }
        let email = grant?.email.flatMap { $0.isEmpty ? nil : $0 }
        return (.google(loginId: loginId), email)
    }
}
