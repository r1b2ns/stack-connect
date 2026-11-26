import Foundation

/// Which accounts use which Apple ID session. One session serves every team
/// account of an Apple ID (plan D4), so it is only removed once its last
/// account is gone, and Add Account can tell which teams are already added.
///
/// `@MainActor` because `KeyStorable` is not `Sendable` (same reasoning as
/// `GoogleLoginReferences`).
@MainActor
enum AppleSessionReferences {

    /// The session reference of an account added with "Sign in with Apple ID",
    /// or `nil` for any other account.
    static func reference(of account: AccountModel, keychain: KeyStorable) -> AppleWebSessionReference? {
        guard account.isAppleIdSession else { return nil }
        let credentials: AppleCredentials? = keychain.object(forKey: "credentials.\(account.id)")
        return credentials?.webSession
    }

    /// The accounts of `accounts` that use `appleId`'s session.
    static func accounts(using appleId: String, in accounts: [AccountModel], keychain: KeyStorable) -> [AccountModel] {
        let id = AppleSessionKeychainStore.normalized(appleId)
        return accounts.filter { reference(of: $0, keychain: keychain)?.appleId == id }
    }

    /// The Apple ID an Apple ID account without a reference (`accountId`)
    /// most likely used, only when it is unambiguous: the single Apple ID
    /// that the other Apple ID accounts of `accounts` use or that has an
    /// expired session. `nil` when there is none or there are several.
    /// A suggestion only (the account itself no longer says): the sign-in
    /// keeps the field editable.
    static func suggestedAppleId(
        forAccountWithoutReference accountId: String,
        in accounts: [AccountModel],
        keychain: KeyStorable,
        status: AppleSessionStatusTracking
    ) -> String? {
        var candidates = Set(accounts.lazy
            .filter { $0.id != accountId }
            .compactMap { reference(of: $0, keychain: keychain)?.appleId })
        candidates.formUnion(status.expiredAppleIds())
        candidates.remove("")
        return candidates.count == 1 ? candidates.first : nil
    }

    /// Removes `appleId`'s session, its saved password and its expiry mark
    /// when no account of `remaining` uses it any more.
    static func releaseSessionIfUnused(
        _ appleId: String,
        remaining: [AccountModel],
        keychain: KeyStorable,
        status: AppleSessionStatusTracking = AppleSessionStatusStore.shared
    ) {
        guard accounts(using: appleId, in: remaining, keychain: keychain).isEmpty else { return }
        AppleSessionKeychainStore(keychain: keychain).deleteSession(for: appleId)
        ApplePasswordKeychainStore(keychain: keychain).deletePassword(for: appleId)
        status.markValid(appleId: appleId)
        Log.print.info("[AppleSession] Removed the Apple ID session and saved password: its last account was deleted")
    }
}
