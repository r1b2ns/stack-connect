import Foundation
import StackCoreRust

/// The Rust core's `SessionStore` port over the Keychain: where the Apple ID
/// web session blob of "Sign in with Apple ID" lives (plan `apple-id-sign-in.md`
/// D3/D4).
///
/// **One item per Apple ID.** The core calls `load` / `save` with the
/// `accountId` the connection passed to `connectWithAppleSession`, and every
/// session account passes its normalized Apple ID there (not its own account
/// id). So all team accounts of one Apple ID read and write the same item,
/// `appleSession.{appleId}`: signing in again replaces the session for every
/// team at once, and the cookies the core refreshes after a response serve
/// the other teams too.
///
/// The blob is opaque (cookies, widget key, team): it is never logged, never
/// decoded here and never leaves the Keychain except to the core.
///
/// Thread-safety: the core calls `save` from its own threads, possibly from
/// several team accounts at once. A lock serializes the Keychain writes (the
/// last write wins, plan Q5); `KeyStorable` itself holds no mutable state.
final class AppleSessionKeychainStore: SessionStore, @unchecked Sendable {

    static let itemPrefix = "appleSession."

    private let keychain: KeyStorable
    private let lock = NSLock()

    init(keychain: KeyStorable = KeychainStorable.shared) {
        self.keychain = keychain
    }

    // MARK: - Keys

    /// The Apple ID as it keys the session: trimmed and lowercased (Apple IDs
    /// are case-insensitive e-mails).
    static func normalized(_ appleId: String) -> String {
        appleId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The Keychain item of `appleId`'s session.
    static func itemKey(appleId: String) -> String {
        itemPrefix + normalized(appleId)
    }

    // MARK: - SessionStore (called by the core)

    func load(accountId: String) -> Data? {
        lock.withLock { keychain.data(forKey: Self.itemKey(appleId: accountId)) }
    }

    func save(accountId: String, blob: Data) {
        lock.withLock { keychain.set(blob, forKey: Self.itemKey(appleId: accountId)) }
    }

    // MARK: - Host side

    /// Whether a session is stored for `appleId`.
    func hasSession(for appleId: String) -> Bool {
        load(accountId: appleId) != nil
    }

    /// Removes `appleId`'s session (its last account was deleted).
    func deleteSession(for appleId: String) {
        lock.withLock { keychain.removeObject(forKey: Self.itemKey(appleId: appleId)) }
    }
}
