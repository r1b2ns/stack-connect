import Foundation

/// Remembers which Google logins Google stopped accepting (`invalid_grant`
/// on a token refresh: the 7-day Testing expiry, a revoked grant, a changed
/// password), so the Home can offer "sign in again" before a screen fails.
/// The counterpart of `AppleSessionStatusStore` for "Sign in with Google".
///
/// Every method is synchronous and thread-safe.
protocol GoogleLoginStatusTracking: Sendable {
    func isExpired(loginId: String) -> Bool
    /// Records the expiry and posts `.signInStatusDidChange` when it is new.
    func markExpired(loginId: String)
    /// Records a working login again (a refresh or a new sign-in), posting
    /// `.signInStatusDidChange` when it was expired.
    func markValid(loginId: String)
}

/// `GoogleLoginStatusTracking` over `UserDefaults`. Stores only Google's
/// user IDs (`sub`) of expired logins: no token, no e-mail.
final class GoogleLoginStatusStore: GoogleLoginStatusTracking, @unchecked Sendable {

    static let shared = GoogleLoginStatusStore()

    static let defaultsKey = "googleLogin.expiredLoginIds"

    private let defaults: UserDefaults
    private let center: NotificationCenter
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, center: NotificationCenter = .default) {
        self.defaults = defaults
        self.center = center
    }

    func isExpired(loginId: String) -> Bool {
        lock.withLock { expired().contains(loginId) }
    }

    func markExpired(loginId: String) {
        let changed: Bool = lock.withLock {
            var ids = expired()
            guard ids.insert(loginId).inserted else { return false }
            defaults.set(ids.sorted(), forKey: Self.defaultsKey)
            return true
        }
        guard changed else { return }
        Log.print.notice("[GoogleAuth] The Google login expired; its accounts need a new sign-in")
        center.postSignInStatusDidChange()
    }

    func markValid(loginId: String) {
        let changed: Bool = lock.withLock {
            var ids = expired()
            guard ids.remove(loginId) != nil else { return false }
            defaults.set(ids.sorted(), forKey: Self.defaultsKey)
            return true
        }
        guard changed else { return }
        center.postSignInStatusDidChange()
    }

    private func expired() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }
}
