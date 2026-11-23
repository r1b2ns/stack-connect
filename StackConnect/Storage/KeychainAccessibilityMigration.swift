import Foundation
import Security

/// One-time move of the Keychain items created before
/// `KeychainAccessibilityPolicy` existed (all `WhenUnlockedThisDeviceOnly`) to
/// the class the policy gives their key: account credentials, Google grants and
/// Apple ID sessions become `AfterFirstUnlockThisDeviceOnly`, so background
/// sync can read them; the saved Apple ID passwords keep `WhenUnlocked`.
///
/// Only `kSecAttrAccessible` is updated — the item data is never read, written
/// or logged (only keys and OSStatus are). Idempotent: items already in their
/// class are skipped. Completion is recorded in `defaults` only once every
/// item was moved; any failure leaves it unrecorded so the next run retries.
/// Must run while protected data is available (`WhenUnlocked` items are
/// unreachable otherwise), see `KeychainProtectedDataMaintenance`.
struct KeychainAccessibilityMigration {

    enum Outcome: Equatable {
        /// Recorded as done by an earlier run: nothing was queried.
        case alreadyCompleted
        /// Every item is now in its class; `migrated` were updated.
        case completed(migrated: Int)
        /// Not recorded: runs again next time.
        case failed
    }

    static let completedDefaultsKey = "keychain.accessibilityMigration.afterFirstUnlock.v1"

    let service: String
    let policy: KeychainAccessibilityPolicy
    let backend: any KeychainBackend
    let defaults: UserDefaults

    init(
        service: String,
        policy: KeychainAccessibilityPolicy,
        backend: any KeychainBackend,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.policy = policy
        self.backend = backend
        self.defaults = defaults
    }

    /// The migration of `keychain`'s items, with its own service and policy.
    init(keychain: KeychainStorable, defaults: UserDefaults = .standard) {
        self.init(service: keychain.service, policy: keychain.accessibilityPolicy,
                  backend: keychain.backend, defaults: defaults)
    }

    var isCompleted: Bool {
        defaults.bool(forKey: Self.completedDefaultsKey)
    }

    @discardableResult
    func runIfNeeded() -> Outcome {
        guard !isCompleted else { return .alreadyCompleted }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        let (status, result) = backend.copyMatching(query)

        let items: [[String: Any]]
        switch status {
        case errSecSuccess:
            items = (result as? [[String: Any]]) ?? []
        case errSecItemNotFound:
            items = []
        default:
            Log.print.error("[Keychain] Accessibility migration could not list items: OSStatus \(status)")
            return .failed
        }

        var migrated = 0
        var failed = false
        for attributes in items {
            guard let key = attributes[kSecAttrAccount as String] as? String else { continue }
            let target = policy.accessibility(forKey: key)
            if attributes[kSecAttrAccessible as String] as? String == target.secValue { continue }

            let itemQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            let updateStatus = backend.update(itemQuery, attributes: [kSecAttrAccessible as String: target.secValue])
            switch updateStatus {
            case errSecSuccess:
                migrated += 1
            case errSecItemNotFound:
                // Deleted in between: nothing left to move.
                break
            default:
                failed = true
                Log.print.error("[Keychain] Accessibility migration failed for key '\(key)': OSStatus \(updateStatus)")
            }
        }

        guard !failed else { return .failed }
        defaults.set(true, forKey: Self.completedDefaultsKey)
        Log.print.notice("[Keychain] Accessibility migration completed (\(migrated) of \(items.count) item(s) updated)")
        return .completed(migrated: migrated)
    }
}
