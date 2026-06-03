import Foundation
import StackCrypto

// `AccountCryptoError` lives in the `StackCrypto` package without any user-facing
// strings, so the type stays portable (no `String(localized:)` / bundle lookups).
// The app re-adds localized descriptions here. The literals match the keys already
// present in `Localizable.xcstrings`, so existing translations keep working and
// `error.localizedDescription` resolves to the localized message at the call sites.
extension AccountCryptoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .encryptionFailed:    return String(localized: "Failed to encrypt data.")
        case .invalidFileFormat:   return String(localized: "Invalid file format. This is not a StackConnect export file.")
        case .unsupportedVersion:  return String(localized: "Unsupported file version.")
        case .decryptionFailed:    return String(localized: "Failed to decrypt file.")
        case .invalidPassword:     return String(localized: "Invalid password or corrupted file.")
        case .keyDerivationFailed: return String(localized: "Failed to derive encryption key.")
        }
    }
}
