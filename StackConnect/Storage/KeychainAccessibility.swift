import Foundation
import Security

/// When a Keychain item can be read. Both classes are device-only: items are
/// never synced through iCloud Keychain nor restored to another device.
enum KeychainAccessibility: Equatable, Sendable {
    /// Readable from the first unlock after boot until the next reboot, locked
    /// device included: what background sync (`BGTask`), a prewarmed launch
    /// and the widget timeline need.
    case afterFirstUnlockThisDeviceOnly
    /// Readable only while the device is unlocked.
    case whenUnlockedThisDeviceOnly

    /// The `kSecAttrAccessible` value.
    var secValue: String {
        switch self {
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        }
    }
}

/// Which accessibility class each key of a `KeychainStorable` gets, decided
/// by key prefix (first matching rule wins), otherwise `defaultAccessibility`.
///
/// Used both when writing an item and by the one-time migration of items
/// created before the policy existed, so the two can never disagree.
struct KeychainAccessibilityPolicy: Sendable {

    struct Rule: Sendable {
        let keyPrefix: String
        let accessibility: KeychainAccessibility
    }

    let defaultAccessibility: KeychainAccessibility
    let rules: [Rule]

    func accessibility(forKey key: String) -> KeychainAccessibility {
        rules.first { key.hasPrefix($0.keyPrefix) }?.accessibility ?? defaultAccessibility
    }

    /// The app's policy: everything — account credentials
    /// (`credentials.{accountId}`), Google login grants, Apple ID web sessions —
    /// is readable after the first unlock so background work can use it, except
    /// the saved Apple ID password, which is only used in the foreground
    /// (`ApplePasswordKeychainStore.accessibility`).
    static let standard = KeychainAccessibilityPolicy(
        defaultAccessibility: .afterFirstUnlockThisDeviceOnly,
        rules: [
            Rule(keyPrefix: ApplePasswordKeychainStore.itemPrefix,
                 accessibility: ApplePasswordKeychainStore.accessibility)
        ]
    )
}
