import Foundation

/// The Apple ID password saved after a successful "Sign in with Apple ID", so
/// signing in again (an expired session) only asks for the two-factor code.
///
/// **One item per Apple ID**, next to its session blob
/// (`AppleSessionKeychainStore`): `applePassword.{normalizedAppleId}`. The
/// Keychain item is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and not
/// synchronizable (`KeychainStorable` writes every item that way), so it never
/// leaves this device, iCloud Keychain and backups to other devices included.
///
/// The password is written only once a sign-in finished (Apple accepted it),
/// removed as soon as Apple refuses it (it changed), and removed with the last
/// account of the Apple ID (`AppleSessionReferences.releaseSessionIfUnused`).
/// It is never logged, exported (`AccountTransferCredentials` only reads
/// `credentials.{accountId}`) or sent anywhere but to the core's `start`.
///
/// Called on the main actor by the sign-in; a lock keeps it safe anyway, like
/// the session store.
final class ApplePasswordKeychainStore: @unchecked Sendable {

    static let itemPrefix = "applePassword."

    private let keychain: KeyStorable
    private let lock = NSLock()

    init(keychain: KeyStorable = KeychainStorable.shared) {
        self.keychain = keychain
    }

    /// The Keychain item of `appleId`'s password (the Apple ID normalized the
    /// way its session is keyed).
    static func itemKey(appleId: String) -> String {
        itemPrefix + AppleSessionKeychainStore.normalized(appleId)
    }

    /// The saved password of `appleId`, or `nil` when none is saved.
    func password(for appleId: String) -> String? {
        lock.withLock {
            guard let password = keychain.string(forKey: Self.itemKey(appleId: appleId)), !password.isEmpty else {
                return nil
            }
            return password
        }
    }

    func hasPassword(for appleId: String) -> Bool {
        password(for: appleId) != nil
    }

    /// Saves (or replaces) `appleId`'s password. An empty one is ignored.
    func save(_ password: String, for appleId: String) {
        guard !password.isEmpty else { return }
        lock.withLock { keychain.set(password, forKey: Self.itemKey(appleId: appleId)) }
    }

    /// Removes `appleId`'s password (Apple refused it, or its last account was
    /// deleted).
    func deletePassword(for appleId: String) {
        lock.withLock { keychain.removeObject(forKey: Self.itemKey(appleId: appleId)) }
    }
}
