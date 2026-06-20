import Foundation
import StackCoreRust

/// Bridges the app's `AppleCredentials` to the Rust core's foreign `CredentialStore`
/// trait so the shared core can read App Store Connect secrets it needs.
///
/// The Rust core asks for three exact keys — `issuerId`, `keyId`, `privateKeyP8` —
/// which map onto `AppleCredentials.issuerID`, `.privateKeyID` and `.privateKey`
/// respectively.
///
/// Scope (read path only): this store is constructed *per connection* and is
/// strictly read-only for now. `setSecret` and `delete` are intentional no-ops —
/// the app remains the single source of truth for credential persistence (Keychain),
/// and the current strangler step (`validate` / `fetchApps`) never writes secrets
/// back through the core. When write-back becomes necessary, these can forward to
/// the app's `KeychainStorable`.
///
/// Thread-safety: the Rust callback may query `secret(accountId:key:)` from any
/// thread, so the captured credentials are immutable `let`s and the type is
/// `@unchecked Sendable` (safe because there is no mutable state).
final class AppleCredentialStore: CredentialStore, @unchecked Sendable {

    /// Exact credential keys the Rust core reads. Centralised to avoid stringly-typed
    /// drift against the core's `credentialSchema(kind: .appStoreConnect)`.
    enum Key {
        static let issuerId = "issuerId"
        static let keyId = "keyId"
        static let privateKeyP8 = "privateKeyP8"
    }

    private let credentials: AppleCredentials

    init(credentials: AppleCredentials) {
        self.credentials = credentials
    }

    // MARK: - CredentialStore

    func secret(accountId: String, key: String) -> String? {
        switch key {
        case Key.issuerId:
            return credentials.issuerID
        case Key.keyId:
            return credentials.privateKeyID
        case Key.privateKeyP8:
            return credentials.privateKey
        default:
            // Unknown key: return nil so the core takes its "missing credentials"
            // path rather than receiving a bogus value.
            return nil
        }
    }

    func setSecret(accountId: String, key: String, value: String) {
        // No-op: read-only bridge for the current strangler step. See type docs.
    }

    func delete(accountId: String) {
        // No-op: credential lifecycle stays in the app (Keychain). See type docs.
    }
}
