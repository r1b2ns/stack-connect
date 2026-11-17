import Foundation

/// Provider credentials as carried in the `credentials` object of a `.scexport`
/// payload. Single source of truth for the payload keys, shared by
/// `AccountExporter` (keychain → payload) and `AccountImporter` (payload →
/// keychain), so the two sides can never drift apart.
///
/// Payload shape per provider (unchanged since the format was introduced):
/// - App Store Connect: `issuerID`, `privateKeyID`, `privateKey`;
/// - Firebase and Google Play: `serviceAccountJSON` (the whole key file).
///
/// Security: the returned dictionaries hold key material — never log them.
enum AccountTransferCredentials {

    /// Keys of the `credentials` object.
    enum Key {
        static let issuerID = "issuerID"
        static let privateKeyID = "privateKeyID"
        static let privateKey = "privateKey"
        static let serviceAccountJSON = "serviceAccountJSON"
    }

    /// The `credentials` payload of an account, read from its keychain entry.
    /// `nil` when nothing is stored for the account or its provider can't be
    /// exported (`ProviderType.supportsExport`).
    static func exportPayload(for account: AccountModel, keychain: KeyStorable) -> [String: String]? {
        let keychainKey = "credentials.\(account.id)"

        switch account.providerType {
        case .apple:
            guard let credentials: AppleCredentials = keychain.object(forKey: keychainKey) else { return nil }
            return [
                Key.issuerID: credentials.issuerID,
                Key.privateKeyID: credentials.privateKeyID,
                Key.privateKey: credentials.privateKey
            ]

        case .googlePlay:
            // Storage format unchanged (plan D2): the whole key file, as stored.
            guard let credentials: GooglePlayCredentials = keychain.object(forKey: keychainKey) else { return nil }
            return [Key.serviceAccountJSON: credentials.serviceAccountJSON]

        case .firebase:
            return nil
        }
    }
}
