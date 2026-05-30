import Foundation

// MARK: - Protocol

@MainActor
protocol AccountsListViewModelProtocol: ObservableObject {
    var uiState: AccountsListUiState { get set }
    func loadAccounts() async
    func deleteAccount(at offsets: IndexSet) async
    func importAccount(from url: URL, password: String, customName: String?) async -> String?
}

// MARK: - UiState

struct AccountsListUiState {
    var accounts: [AccountModel] = []
    var isLoading = false
    var providerType: ProviderType
}

// MARK: - Implementation

@MainActor
final class AccountsListViewModel: AccountsListViewModelProtocol {

    @Published var uiState: AccountsListUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        providerType: ProviderType,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.uiState = AccountsListUiState(providerType: providerType)
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func loadAccounts() async {
        uiState.isLoading = true
        do {
            var allAccounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            for i in allAccounts.indices { allAccounts[i].fillMissingRules() }
            uiState.accounts = allAccounts.filter { $0.providerType == uiState.providerType }
        } catch {
            Log.print.error("[AccountsList] Failed to load accounts: \(error.localizedDescription)")
        }
        uiState.isLoading = false
    }

    func deleteAccount(at offsets: IndexSet) async {
        for index in offsets {
            let account = uiState.accounts[index]
            do {
                // Delete all apps belonging to this account
                let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
                let accountApps = allApps.filter { $0.accountId == account.id }
                for app in accountApps {
                    let allVersions: [AppStoreVersionModel] = try await storage.fetchAll(AppStoreVersionModel.self)
                    let appVersions = allVersions.filter { $0.appId == app.id }
                    for version in appVersions {
                        try? await storage.delete(AppStoreVersionModel.self, id: "version.\(version.id)")
                    }
                    try? await storage.delete(AppModel.self, id: "\(account.id).\(app.id)")
                }

                try await storage.delete(AccountModel.self, id: account.id)
                keychain.removeObject(forKey: "credentials.\(account.id)")
                Log.print.info("[AccountsList] Deleted account and related data: \(account.name)")
            } catch {
                Log.print.error("[AccountsList] Failed to delete account: \(error.localizedDescription)")
            }
        }
        uiState.accounts.remove(atOffsets: offsets)
    }

    // MARK: - Import

    func importAccount(from url: URL, password: String, customName: String?) async -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return String(localized: "Failed to read file.")
        }

        let jsonString: String
        do {
            jsonString = try AccountCrypto.decrypt(data: data, password: password)
        } catch {
            return error.localizedDescription
        }

        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return String(localized: "Invalid JSON format.")
        }

        guard let name = dict["name"] as? String, !name.isEmpty else {
            return String(localized: "Missing or invalid 'name' field.")
        }
        guard let providerRaw = dict["providerType"] as? String,
              let providerType = ProviderType(rawValue: providerRaw) else {
            return String(localized: "Missing or invalid 'providerType' field.")
        }

        // Validate provider matches this list
        guard providerType == uiState.providerType else {
            return String(localized: "This file contains a \(providerType.displayName) account, but this is the \(uiState.providerType.displayName) section.")
        }

        let emptyRules = AccountRules()
        var rules = emptyRules
        if let rulesDict = dict["rules"] as? [String: [String]] {
            rules = AccountRules(
                apps: rulesDict["apps"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                version: rulesDict["version"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                users: rulesDict["users"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                review: rulesDict["review"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                testFlight: rulesDict["testFlight"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                analytics: rulesDict["analytics"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                provisioning: rulesDict["provisioning"]?.compactMap { AccountPermission(rawValue: $0) } ?? []
            )
        }

        guard let credsDict = dict["credentials"] as? [String: String] else {
            return String(localized: "Missing or invalid 'credentials' field.")
        }

        // Check for duplicate credentials
        let allAccounts = (try? await storage.fetchAll(AccountModel.self)) ?? []
        let sameTypeAccounts = allAccounts.filter { $0.providerType == providerType }

        let accountId = UUID().uuidString

        switch providerType {
        case .apple:
            guard let issuerID = credsDict["issuerID"], !issuerID.isEmpty,
                  let privateKeyID = credsDict["privateKeyID"], !privateKeyID.isEmpty,
                  let privateKey = credsDict["privateKey"], !privateKey.isEmpty else {
                return String(localized: "Invalid Apple credentials. Required: issuerID, privateKeyID, privateKey.")
            }
            for existing in sameTypeAccounts {
                if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.privateKey == privateKey {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            let credentials = AppleCredentials(issuerID: issuerID, privateKeyID: privateKeyID, privateKey: privateKey)
            keychain.setObject(credentials, forKey: "credentials.\(accountId)")
        case .firebase:
            guard let json = credsDict["serviceAccountJSON"], !json.isEmpty else {
                return String(localized: "Invalid Firebase credentials. Required: serviceAccountJSON.")
            }
            for existing in sameTypeAccounts {
                if let creds: FirebaseCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.serviceAccountJSON == json {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            let credentials = FirebaseCredentials(serviceAccountJSON: json)
            keychain.setObject(credentials, forKey: "credentials.\(accountId)")
        case .googlePlay:
            guard let json = credsDict["serviceAccountJSON"], !json.isEmpty else {
                return String(localized: "Invalid Google Play credentials. Required: serviceAccountJSON.")
            }
            for existing in sameTypeAccounts {
                if let creds: GooglePlayCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.serviceAccountJSON == json {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            let credentials = GooglePlayCredentials(serviceAccountJSON: json)
            keychain.setObject(credentials, forKey: "credentials.\(accountId)")
        }

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
            Log.print.info("[AccountsList] Imported account: \(accountName)")
            await loadAccounts()
            return nil
        } catch {
            return String(localized: "Failed to save imported account: \(error.localizedDescription)")
        }
    }
}
