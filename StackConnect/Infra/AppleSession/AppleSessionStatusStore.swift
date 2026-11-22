import Foundation

extension Notification.Name {
    /// Posted on the main thread each time App Store Connect refuses an Apple
    /// ID session. `object` is the normalized Apple ID (`String`);
    /// `userInfo[AppleSessionStatusStore.isNewKey]` is `true` only for the
    /// first refusal after the session last worked.
    static let appleSessionDidExpire = Notification.Name("StackConnect.appleSessionDidExpire")
}

/// Remembers which Apple ID sessions App Store Connect stopped accepting
/// (`StackError.SessionExpired`), so the background refresh skips their
/// accounts (plan D7) and the app can ask the user to sign in again (D5).
///
/// Called from the connections, which run off the main actor: every method is
/// synchronous and thread-safe.
protocol AppleSessionStatusTracking: Sendable {
    func isExpired(appleId: String) -> Bool
    /// Records the expiry and posts `.appleSessionDidExpire` (and
    /// `.signInStatusDidChange` when the expiry is new).
    func markExpired(appleId: String)
    /// Records a working session again (a successful call, or a new sign-in),
    /// posting `.signInStatusDidChange` when it was expired.
    func markValid(appleId: String)
}

/// `AppleSessionStatusTracking` over `UserDefaults`. Stores only the Apple ID
/// e-mails of expired sessions (no secret: the session stays in the Keychain).
final class AppleSessionStatusStore: AppleSessionStatusTracking, @unchecked Sendable {

    static let shared = AppleSessionStatusStore()

    static let defaultsKey = "appleSession.expiredAppleIds"
    /// `userInfo` key of `.appleSessionDidExpire`: whether the expiry is new.
    static let isNewKey = "isNew"

    private let defaults: UserDefaults
    private let center: NotificationCenter
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, center: NotificationCenter = .default) {
        self.defaults = defaults
        self.center = center
    }

    func isExpired(appleId: String) -> Bool {
        lock.withLock { expired().contains(AppleSessionKeychainStore.normalized(appleId)) }
    }

    func markExpired(appleId: String) {
        let id = AppleSessionKeychainStore.normalized(appleId)
        let isNew: Bool = lock.withLock {
            var ids = expired()
            guard ids.insert(id).inserted else { return false }
            defaults.set(ids.sorted(), forKey: Self.defaultsKey)
            return true
        }
        if isNew {
            Log.print.notice("[AppleSession] The Apple ID session expired; the accounts need a new sign-in")
        }
        let center = self.center
        let userInfo = [Self.isNewKey: isNew]
        if Thread.isMainThread {
            center.post(name: .appleSessionDidExpire, object: id, userInfo: userInfo)
        } else {
            DispatchQueue.main.async { center.post(name: .appleSessionDidExpire, object: id, userInfo: userInfo) }
        }
        if isNew {
            center.postSignInStatusDidChange()
        }
    }

    func markValid(appleId: String) {
        let id = AppleSessionKeychainStore.normalized(appleId)
        let changed: Bool = lock.withLock {
            var ids = expired()
            guard ids.remove(id) != nil else { return false }
            defaults.set(ids.sorted(), forKey: Self.defaultsKey)
            return true
        }
        if changed {
            center.postSignInStatusDidChange()
        }
    }

    private func expired() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }
}
