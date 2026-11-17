import Foundation
import StackCoreRust

/// Bridges a parsed `GooglePlayServiceAccount` to the Rust core's foreign
/// `CredentialStore` trait so the shared core can sign Google OAuth assertions.
///
/// The core asks for three exact keys — `clientEmail`, `privateKeyId`,
/// `privateKey` — which map onto the service-account JSON's `client_email`,
/// `private_key_id` and `private_key`. The core never receives the whole JSON
/// file: it rejects one passed as `privateKey`.
///
/// Scope (read path only), same as `AppleCredentialStore`: the store is built
/// *per connection* and is strictly read-only. `setSecret` and `delete` are
/// intentional no-ops — the Keychain (`GooglePlayCredentials`) stays the single
/// source of truth for credential persistence.
///
/// Thread-safety: the Rust callback may query `secret(accountId:key:)` from any
/// thread; the only stored property is an immutable `Sendable` value, so the
/// type is checked-`Sendable` without locks.
final class GooglePlayCredentialStore: CredentialStore {

    /// Exact credential keys the Rust core reads. Centralised to avoid stringly-typed
    /// drift against the core's `credentialSchema(kind: .googlePlay)`.
    enum Key {
        static let clientEmail = "clientEmail"
        static let privateKeyId = "privateKeyId"
        static let privateKey = "privateKey"
    }

    private let serviceAccount: GooglePlayServiceAccount

    init(serviceAccount: GooglePlayServiceAccount) {
        self.serviceAccount = serviceAccount
    }

    // MARK: - CredentialStore

    func secret(accountId: String, key: String) -> String? {
        switch key {
        case Key.clientEmail:
            return serviceAccount.clientEmail
        case Key.privateKeyId:
            return serviceAccount.privateKeyId
        case Key.privateKey:
            return serviceAccount.privateKey
        default:
            // Unknown key: return nil so the core takes its "missing credentials"
            // path rather than receiving a bogus value.
            return nil
        }
    }

    func setSecret(accountId: String, key: String, value: String) {
        // No-op: read-only bridge. See type docs.
    }

    func delete(accountId: String) {
        // No-op: credential lifecycle stays in the app (Keychain). See type docs.
    }
}
