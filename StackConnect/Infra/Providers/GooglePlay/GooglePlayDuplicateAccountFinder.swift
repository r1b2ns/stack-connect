import Foundation

/// Finds an already registered Google Play account backed by the same service
/// account as a key file (plan D4).
///
/// Identity is the service account's `client_email`, compared case-insensitively
/// — never the raw JSON — so a re-formatted, re-downloaded or rotated key of the
/// same service account is still caught. Shared by Add Account and both
/// `.scexport` import paths (`AccountImporter`).
enum GooglePlayDuplicateAccountFinder {

    /// Lower-cased `client_email` of a service-account key file, or `nil` when the
    /// key can't be parsed.
    static func identity(of serviceAccountJSON: String) -> String? {
        (try? GooglePlayServiceAccount(json: serviceAccountJSON))?.clientEmail.lowercased()
    }

    /// The first Google Play account in `accounts` whose stored key belongs to the
    /// same service account as `serviceAccountJSON`.
    ///
    /// Returns `nil` when the new key can't be parsed: an unusable key is not a
    /// duplicate, and the caller reports why it can't be used.
    static func existingAccount(
        matching serviceAccountJSON: String,
        in accounts: [AccountModel],
        keychain: KeyStorable
    ) -> AccountModel? {
        guard let newIdentity = identity(of: serviceAccountJSON) else { return nil }

        return accounts.first { account in
            guard account.providerType == .googlePlay,
                  let credentials: GooglePlayCredentials = keychain.object(forKey: "credentials.\(account.id)") else {
                return false
            }
            return identity(of: credentials.serviceAccountJSON) == newIdentity
        }
    }
}
