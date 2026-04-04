import Foundation

// MARK: - Protocol

@MainActor
protocol SettingsAccountsViewModelProtocol: ObservableObject {
    var uiState: SettingsAccountsUiState { get set }
    func loadAccounts() async
    func updateAccountName(accountId: String, newName: String) async
    func deleteAccount(_ account: AccountModel) async
    func exportAccountWithRules(account: AccountModel, exportName: String, rules: AccountRules, password: String) -> URL?
    func importAccount(from url: URL, password: String, customName: String?) async -> String?
}

// MARK: - UiState

struct SettingsAccountsUiState {
    var appleAccounts: [AccountModel] = []
    var firebaseAccounts: [AccountModel] = []
    var googlePlayAccounts: [AccountModel] = []
    var isLoading = false
    var editingName = ""
    var accountToDelete: AccountModel?
    var showDeleteConfirmation = false
    var exportFileURL: URL?
    var showExportShare = false
}

// MARK: - Implementation

@MainActor
final class SettingsAccountsViewModel: SettingsAccountsViewModelProtocol {

    @Published var uiState = SettingsAccountsUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func loadAccounts() async {
        uiState.isLoading = true
        do {
            var allAccounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)

            // Fill missing rules for legacy accounts
            for i in allAccounts.indices {
                allAccounts[i].fillMissingRules()
            }

            uiState.appleAccounts = allAccounts
                .filter { $0.providerType == .apple }
                .sorted { $0.name < $1.name }
            uiState.firebaseAccounts = allAccounts
                .filter { $0.providerType == .firebase }
                .sorted { $0.name < $1.name }
            uiState.googlePlayAccounts = allAccounts
                .filter { $0.providerType == .googlePlay }
                .sorted { $0.name < $1.name }
        } catch {
            Log.print.error("[SettingsAccounts] Failed to load accounts: \(error.localizedDescription)")
        }
        uiState.isLoading = false
    }

    func updateAccountName(accountId: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Find the account in any list
        let allAccounts = uiState.appleAccounts + uiState.firebaseAccounts + uiState.googlePlayAccounts
        guard let existing = allAccounts.first(where: { $0.id == accountId }) else { return }

        let updated = AccountModel(
            id: existing.id,
            name: trimmed,
            providerType: existing.providerType,
            createdAt: existing.createdAt
        )

        do {
            try await storage.save(updated, id: updated.id)
            Log.print.info("[SettingsAccounts] Updated account name: \(trimmed)")
            await loadAccounts()
        } catch {
            Log.print.error("[SettingsAccounts] Failed to update account: \(error.localizedDescription)")
        }
    }

    func deleteAccount(_ account: AccountModel) async {
        do {
            // Delete all apps belonging to this account
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let accountApps = allApps.filter { $0.accountId == account.id }
            for app in accountApps {
                // Delete versions for each app
                let allVersions: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)
                let appVersions = allVersions.filter { $0.appId == app.id }
                for version in appVersions {
                    try? await storage.delete(AppStoreVersionModel.self, id: "version.\(version.id)")
                }
                try? await storage.delete(AppModel.self, id: "\(account.id).\(app.id)")
            }

            // Delete account and credentials
            try await storage.delete(AccountModel.self, id: account.id)
            keychain.removeObject(forKey: "credentials.\(account.id)")
            Log.print.info("[SettingsAccounts] Deleted account and related data: \(account.name)")
            await loadAccounts()
        } catch {
            Log.print.error("[SettingsAccounts] Failed to delete account: \(error.localizedDescription)")
        }
    }

    func exportAccountWithRules(account: AccountModel, exportName: String, rules: AccountRules, password: String) -> URL? {
        var exportDict: [String: Any] = [
            "id": account.id,
            "name": exportName,
            "providerType": account.providerType.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: account.createdAt)
        ]

        exportDict["rules"] = [
            "apps": rules.apps.map(\.rawValue),
            "version": rules.version.map(\.rawValue),
            "users": rules.users.map(\.rawValue),
            "review": rules.review.map(\.rawValue),
            "testFlight": rules.testFlight.map(\.rawValue),
            "analytics": rules.analytics.map(\.rawValue)
        ]

        if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") {
            exportDict["credentials"] = [
                "issuerID": creds.issuerID,
                "privateKeyID": creds.privateKeyID,
                "privateKey": creds.privateKey
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Encrypt the JSON
        guard let encryptedData = try? AccountCrypto.encrypt(json: json, password: password) else {
            Log.print.error("[SettingsAccounts] Failed to encrypt export data")
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let sanitizedName = exportName
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let accountType = account.providerType.rawValue
        let fileName = "\(sanitizedName)-stackconnect-\(accountType)-\(dateString).scexport"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try encryptedData.write(to: tempURL)
            return tempURL
        } catch {
            Log.print.error("[SettingsAccounts] Failed to write export file: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Import

    func importAccount(from url: URL, password: String, customName: String?) async -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // 1. Read file
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return String(localized: "Failed to read file.")
        }

        // 2. Decrypt
        let jsonString: String
        do {
            jsonString = try AccountCrypto.decrypt(data: data, password: password)
        } catch {
            return error.localizedDescription
        }

        // 3. Parse JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return String(localized: "Invalid JSON format.")
        }

        // 3. Validate required fields
        guard let name = dict["name"] as? String, !name.isEmpty else {
            return String(localized: "Missing or invalid 'name' field.")
        }
        guard let providerRaw = dict["providerType"] as? String,
              let providerType = ProviderType(rawValue: providerRaw) else {
            return String(localized: "Missing or invalid 'providerType' field.")
        }

        // 4. Parse rules — use what's in the file; if absent, default to empty (no permissions)
        let emptyRules = AccountRules(apps: [], version: [], users: [], review: [], testFlight: [], analytics: [])
        var rules = emptyRules
        if let rulesDict = dict["rules"] as? [String: [String]] {
            rules = AccountRules(
                apps: rulesDict["apps"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                version: rulesDict["version"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                users: rulesDict["users"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                review: rulesDict["review"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                testFlight: rulesDict["testFlight"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                analytics: rulesDict["analytics"]?.compactMap { AccountPermission(rawValue: $0) } ?? []
            )
        }

        // 5. Validate and store credentials
        guard let credsDict = dict["credentials"] as? [String: String] else {
            return String(localized: "Missing or invalid 'credentials' field.")
        }

        // Check for duplicate credentials
        let allAccounts = (try? await storage.fetchAll(AccountModel.self)) ?? []
        let sameTypeAccounts = allAccounts.filter { $0.providerType == providerType }

        // Generate new ID for the imported account
        let accountId = UUID().uuidString

        switch providerType {
        case .apple:
            guard let issuerID = credsDict["issuerID"], !issuerID.isEmpty,
                  let privateKeyID = credsDict["privateKeyID"], !privateKeyID.isEmpty,
                  let privateKey = credsDict["privateKey"], !privateKey.isEmpty else {
                return String(localized: "Invalid Apple credentials. Required: issuerID, privateKeyID, privateKey.")
            }
            // Duplicate check
            for existing in sameTypeAccounts {
                if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.privateKey == privateKey {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            let credentials = AppleCredentials(
                issuerID: issuerID,
                privateKeyID: privateKeyID,
                privateKey: privateKey
            )
            keychain.setObject(credentials, forKey: "credentials.\(accountId)")

        case .firebase:
            guard let serviceAccountJSON = credsDict["serviceAccountJSON"], !serviceAccountJSON.isEmpty else {
                return String(localized: "Invalid Firebase credentials. Required: serviceAccountJSON.")
            }
            for existing in sameTypeAccounts {
                if let creds: FirebaseCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.serviceAccountJSON == serviceAccountJSON {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            let credentials = FirebaseCredentials(serviceAccountJSON: serviceAccountJSON)
            keychain.setObject(credentials, forKey: "credentials.\(accountId)")

        case .googlePlay:
            guard let serviceAccountJSON = credsDict["serviceAccountJSON"], !serviceAccountJSON.isEmpty else {
                return String(localized: "Invalid Google Play credentials. Required: serviceAccountJSON.")
            }
            for existing in sameTypeAccounts {
                if let creds: GooglePlayCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.serviceAccountJSON == serviceAccountJSON {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            let credentials = GooglePlayCredentials(serviceAccountJSON: serviceAccountJSON)
            keychain.setObject(credentials, forKey: "credentials.\(accountId)")
        }

        // 6. Create and save account
        let accountName = (customName?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            ? customName!.trimmingCharacters(in: .whitespaces)
            : name
        let account = AccountModel(
            id: accountId,
            name: accountName,
            providerType: providerType,
            rules: rules,
            origin: .imported
        )

        do {
            try await storage.save(account, id: account.id)
            Log.print.info("[SettingsAccounts] Imported account: \(name) (\(providerType.displayName))")
            await loadAccounts()
            return nil // success
        } catch {
            return String(localized: "Failed to save imported account: \(error.localizedDescription)")
        }
    }
}
