import Foundation
import Security

/// The four Security framework calls `KeychainStorable` and
/// `KeychainAccessibilityMigration` make, behind a seam so tests can simulate
/// the Keychain's answers (`errSecInteractionNotAllowed` while the device is
/// locked, `errSecItemNotFound`, success) without touching the real Keychain.
///
/// Queries and attributes use the `kSec…` constants as `String` keys.
protocol KeychainBackend: Sendable {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: AnyObject?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

/// The real Keychain.
struct SecurityKeychainBackend: KeychainBackend {

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: AnyObject?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
