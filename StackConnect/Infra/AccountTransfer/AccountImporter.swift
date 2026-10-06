import Foundation

// MARK: - Errors

/// Why an import saved nothing. `message` is user-facing copy, shown as is by
/// the import alert.
struct AccountImportError: Error, Equatable {
    let message: String
}

// MARK: - Importer

/// Imports an encrypted `.scexport` account file: decrypt → parse → validate →
/// store the credentials in the keychain → save the `AccountModel`.
///
/// Shared by Settings › Accounts and the per-provider Accounts list so both
/// import paths accept and reject exactly the same files, for every provider.
///
/// Validation is offline only — as it always was for App Store Connect: the
/// credentials are checked for shape, never against the live service. A Google
/// Play key must parse (`GooglePlayServiceAccount`); nothing is written to the
/// keychain or storage unless every check passes.
///
/// Backward compatibility: the payload shape is read exactly as before. Absent
/// `rules` ⇒ no permissions; absent `role` ⇒ `.unspecified`; absent / null /
/// empty `appsBundles` ⇒ all apps (`AccountModel.allowsApp(bundleId:)`).
///
/// `@MainActor` because callers are `@MainActor` ViewModels and `KeyStorable` is
/// not `Sendable` (same reasoning as `AccountCascadeDeleter`).
@MainActor
struct AccountImporter {

    /// Restricts or redirects an import.
    struct Options {
        /// When set, files of any other provider are rejected (per-provider list).
        var expectedProvider: ProviderType?
        /// When set, the imported account replaces this one in place (same id),
        /// so its offline data stays linked (re-import of an expired account).
        var replacingAccountId: String?

        init(expectedProvider: ProviderType? = nil, replacingAccountId: String? = nil) {
            self.expectedProvider = expectedProvider
            self.replacingAccountId = replacingAccountId
        }
    }

    private typealias Key = AccountTransferCredentials.Key

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(storage: PersistentStorable, keychain: KeyStorable) {
        self.storage = storage
        self.keychain = keychain
    }

    /// - Returns: the saved account, or why nothing was saved.
    func importAccount(
        from url: URL,
        password: String,
        customName: String?,
        options: Options = Options()
    ) async -> Result<AccountModel, AccountImportError> {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // 1. Read file
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return failure(String(localized: "Failed to read file."))
        }

        // 2. Decrypt
        let jsonString: String
        do {
            jsonString = try AccountCrypto.decrypt(data: data, password: password)
        } catch {
            return failure(error.localizedDescription)
        }

        // 3. Parse JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return failure(String(localized: "Invalid JSON format."))
        }

        // 4. Validate required fields
        guard let name = dict["name"] as? String, !name.isEmpty else {
            return failure(String(localized: "Missing or invalid 'name' field."))
        }
        guard let providerRaw = dict["providerType"] as? String,
              let providerType = ProviderType(rawValue: providerRaw) else {
            return failure(String(localized: "Missing or invalid 'providerType' field."))
        }
        if let expectedProvider = options.expectedProvider, providerType != expectedProvider {
            return failure(String(localized: "This file contains a \(providerType.displayName) account, but this is the \(expectedProvider.displayName) section."))
        }

        // 5. Optional fields
        let rules = Self.parseRules(dict["rules"])

        var expirationDate: Date?
        if let expirationRaw = dict["expirationDate"] as? String {
            expirationDate = ISO8601DateFormatter().date(from: expirationRaw)
        }

        // Backward compatible: absent → .unspecified. Providers without roles
        // (Google Play) always keep the default role.
        let parsedRole = (dict["role"] as? String).flatMap(AccountRole.init(rawValue:)) ?? .unspecified
        let role = providerType.supportsAccountRole ? parsedRole : .unspecified

        // Per-app scope. Absent/null ⇒ nil ⇒ no restriction. Empty ⇒ also no
        // restriction (see AccountModel.allowsApp). Tolerant of a heterogeneous
        // [Any] shape from JSONSerialization.
        let appsBundles = (dict["appsBundles"] as? [String])
            ?? (dict["appsBundles"] as? [Any])?.compactMap { $0 as? String }

        // 6. Credentials: validate, check duplicates, store
        guard let credentials = dict["credentials"] as? [String: String] else {
            return failure(String(localized: "Missing or invalid 'credentials' field."))
        }

        // A re-import reuses the replaced account's id so its offline data stays linked.
        let accountId = options.replacingAccountId ?? UUID().uuidString

        // Effective name used both for the duplicate check and the saved account.
        let trimmedCustomName = customName?.trimmingCharacters(in: .whitespaces) ?? ""
        let accountName = trimmedCustomName.isEmpty ? name : trimmedCustomName

        // Duplicate candidates: same provider, ignoring the account being replaced.
        let allAccounts = (try? await storage.fetchAll(AccountModel.self)) ?? []
        let sameTypeAccounts = allAccounts.filter { $0.providerType == providerType && $0.id != accountId }

        if let credentialsError = storeCredentials(
            credentials,
            providerType: providerType,
            accountId: accountId,
            accountName: accountName,
            existingAccounts: sameTypeAccounts
        ) {
            return failure(credentialsError)
        }

        // 7. Create and save the account
        let account = AccountModel(
            id: accountId,
            name: accountName,
            providerType: providerType,
            rules: rules,
            origin: .imported,
            role: role,
            expirationDate: expirationDate,
            appsBundles: appsBundles
        )

        do {
            try await storage.save(account, id: account.id)
            return .success(account)
        } catch {
            return failure(String(localized: "Failed to save imported account: \(error.localizedDescription)"))
        }
    }

    // MARK: - Private

    private func failure(_ message: String) -> Result<AccountModel, AccountImportError> {
        .failure(AccountImportError(message: message))
    }

    /// Rules in the file; absent ⇒ empty (no permissions).
    private static func parseRules(_ value: Any?) -> AccountRules {
        guard let rulesDict = value as? [String: [String]] else { return AccountRules() }

        func permissions(_ key: String) -> [AccountPermission] {
            rulesDict[key]?.compactMap { AccountPermission(rawValue: $0) } ?? []
        }

        return AccountRules(
            apps: permissions("apps"),
            version: permissions("version"),
            users: permissions("users"),
            review: permissions("review"),
            testFlight: permissions("testFlight"),
            analytics: permissions("analytics"),
            provisioning: permissions("provisioning")
        )
    }

    /// Validates the provider credentials, rejects duplicates and stores them in
    /// the keychain under the new account id.
    ///
    /// - Returns: a user-facing error (nothing stored), or `nil` once stored.
    private func storeCredentials(
        _ credentials: [String: String],
        providerType: ProviderType,
        accountId: String,
        accountName: String,
        existingAccounts: [AccountModel]
    ) -> String? {
        let keychainKey = "credentials.\(accountId)"

        switch providerType {
        case .apple:
            guard let issuerID = credentials[Key.issuerID], !issuerID.isEmpty,
                  let privateKeyID = credentials[Key.privateKeyID], !privateKeyID.isEmpty,
                  let privateKey = credentials[Key.privateKey], !privateKey.isEmpty else {
                return String(localized: "Invalid Apple credentials. Required: issuerID, privateKeyID, privateKey.")
            }
            // Same team key may be re-registered under a different name/role.
            // Only block an EXACT duplicate: same private key AND same account name.
            for existing in existingAccounts {
                if let stored: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   stored.privateKey == privateKey, existing.name == accountName {
                    return Self.duplicateMessage(existing)
                }
            }
            keychain.setObject(
                AppleCredentials(issuerID: issuerID, privateKeyID: privateKeyID, privateKey: privateKey),
                forKey: keychainKey
            )

        case .firebase:
            guard let json = credentials[Key.serviceAccountJSON], !json.isEmpty else {
                return String(localized: "Invalid Firebase credentials. Required: serviceAccountJSON.")
            }
            for existing in existingAccounts {
                if let stored: FirebaseCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   stored.serviceAccountJSON == json {
                    return Self.duplicateMessage(existing)
                }
            }
            keychain.setObject(FirebaseCredentials(serviceAccountJSON: json), forKey: keychainKey)

        case .googlePlay:
            guard let json = credentials[Key.serviceAccountJSON], !json.isEmpty else {
                return String(localized: "Invalid Google Play credentials. Required: serviceAccountJSON.")
            }
            // Shape check only, no network (same policy as the Apple path). The
            // parse error is not logged: the key file must never reach the logs.
            guard (try? GooglePlayServiceAccount(json: json)) != nil else {
                Log.print.error("[AccountImporter] Rejected a Google Play file with an unusable service account key")
                return String(localized: "The Google Play service account key in this file is invalid. Ask the sender to export the account again.")
            }
            // Same service account = same client_email (plan D4).
            if let existing = GooglePlayDuplicateAccountFinder.existingAccount(
                matching: json,
                in: existingAccounts,
                keychain: keychain
            ) {
                return Self.duplicateMessage(existing)
            }
            // Storage format unchanged (plan D2): the whole key file, as exported.
            keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: keychainKey)
        }

        return nil
    }

    private static func duplicateMessage(_ existing: AccountModel) -> String {
        String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
    }
}
