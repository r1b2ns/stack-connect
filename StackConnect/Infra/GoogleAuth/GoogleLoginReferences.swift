import Foundation

/// Which accounts use which Google login. A login is shared by every account
/// added with the same Google user (plan G5), so it is only signed out once
/// its last account is gone, and Add Account can tell what is already added.
///
/// `@MainActor` because `KeyStorable` is not `Sendable` (same reasoning as
/// `AccountCascadeDeleter`).
@MainActor
enum GoogleLoginReferences {

    /// The Google login an account authenticates with, or `nil` for any other
    /// account (key file, App Store Connect, missing credentials).
    static func loginId(of account: AccountModel, keychain: KeyStorable) -> String? {
        let key = "credentials.\(account.id)"
        switch account.providerType {
        case .googlePlay:
            let credentials: GooglePlayCredentials? = keychain.object(forKey: key)
            return credentials?.source.googleLoginId
        case .firebase:
            let credentials: FirebaseCredentials? = keychain.object(forKey: key)
            return credentials?.source.googleLoginId
        case .apple:
            return nil
        }
    }

    /// The e-mail of the Google login an account uses (stored with its grant),
    /// for copy that names the signed-in Google account. `nil` for any other
    /// account, or when Google sent no e-mail.
    static func email(of account: AccountModel, keychain: KeyStorable) -> String? {
        guard account.authMethod == .googleSignIn, let loginId = loginId(of: account, keychain: keychain) else { return nil }
        let email = GoogleLoginKeychainStore(keychain: keychain).load(loginId: loginId)?.email
        return email?.isEmpty == false ? email : nil
    }

    /// The accounts of `accounts` that use `loginId`.
    static func accounts(using loginId: String, in accounts: [AccountModel], keychain: KeyStorable) -> [AccountModel] {
        accounts.filter { $0.authMethod == .googleSignIn && Self.loginId(of: $0, keychain: keychain) == loginId }
    }
}
