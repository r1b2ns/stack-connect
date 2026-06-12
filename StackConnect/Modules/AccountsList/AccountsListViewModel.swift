import Foundation

// MARK: - Protocol

@MainActor
protocol AccountsListViewModelProtocol: ObservableObject {
    var uiState: AccountsListUiState { get set }
    func loadAccounts() async
    func deleteAccount(at offsets: IndexSet) async
    func deleteAccount(_ account: AccountModel) async
    func beginReimport(accountId: String)
    func importAccount(from url: URL, password: String, customName: String?) async -> String?
}

// MARK: - Account Group

/// Groups accounts of the same team. Apple accounts are grouped by their
/// keychain-backed `issuerID`; non-Apple providers form a single "all" group.
struct AccountGroup: Identifiable, Hashable {
    let id: String          // issuerID for apple, or "all" for others, "unknown" when unreadable
    let issuerID: String?   // nil for non-apple / unknown
    let accounts: [AccountModel]
}

// MARK: - UiState

struct AccountsListUiState {
    var accounts: [AccountModel] = []
    var groups: [AccountGroup] = []
    var isLoading = false
    var providerType: ProviderType
    /// When set, the next import replaces this account in place, preserving its offline app data.
    var replacingAccountId: String?

    /// Team grouping is only meaningful when at least one team (issuerID) holds
    /// more than one account. Otherwise the list is shown flat, without headers.
    var showsTeamGroups: Bool {
        groups.contains { $0.issuerID != nil && $0.accounts.count > 1 }
    }
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
            uiState.groups = buildGroups(from: uiState.accounts)
        } catch {
            Log.print.error("[AccountsList] Failed to load accounts: \(error.localizedDescription)")
        }
        uiState.isLoading = false
    }

    /// Groups the filtered accounts by team. Apple accounts are grouped by the
    /// `issuerID` stored in their keychain credentials; accounts whose credentials
    /// can't be read fall into an "unknown" group. Non-Apple providers form a
    /// single "all" group. Groups are sorted deterministically and accounts
    /// within each group are sorted by name.
    private func buildGroups(from accounts: [AccountModel]) -> [AccountGroup] {
        guard uiState.providerType == .apple else {
            let sorted = accounts.sorted { $0.name < $1.name }
            return sorted.isEmpty ? [] : [AccountGroup(id: "all", issuerID: nil, accounts: sorted)]
        }

        var byIssuer: [String: [AccountModel]] = [:]
        for account in accounts {
            let creds: AppleCredentials? = keychain.object(forKey: "credentials.\(account.id)")
            let key = creds?.issuerID ?? "unknown"
            byIssuer[key, default: []].append(account)
        }

        return byIssuer
            .sorted { $0.key < $1.key }
            .map { key, accounts in
                AccountGroup(
                    id: key,
                    issuerID: key == "unknown" ? nil : key,
                    accounts: accounts.sorted { $0.name < $1.name }
                )
            }
    }

    func deleteAccount(at offsets: IndexSet) async {
        for index in offsets {
            await cascadeDelete(uiState.accounts[index])
        }
        uiState.accounts.remove(atOffsets: offsets)
    }

    /// Deletes a single account (and its related data) then reloads. Used by the
    /// grouped list where index-based deletion is not available.
    func deleteAccount(_ account: AccountModel) async {
        await cascadeDelete(account)
        await loadAccounts()
    }

    /// Removes an account along with its apps, versions and keychain credentials.
    private func cascadeDelete(_ account: AccountModel) async {
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

    // MARK: - Re-import

    func beginReimport(accountId: String) {
        uiState.replacingAccountId = accountId
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

        var expirationDate: Date?
        if let expirationRaw = dict["expirationDate"] as? String {
            expirationDate = ISO8601DateFormatter().date(from: expirationRaw)
        }

        // Parse optional role (backward compatible: absent → .unspecified)
        let role = (dict["role"] as? String).flatMap(AccountRole.init(rawValue:)) ?? .unspecified

        guard let credsDict = dict["credentials"] as? [String: String] else {
            return String(localized: "Missing or invalid 'credentials' field.")
        }

        // When re-importing, reuse the expired account's id so its offline apps stay linked.
        let accountId = uiState.replacingAccountId ?? UUID().uuidString

        // Check for duplicate credentials (ignore the account being replaced)
        let allAccounts = (try? await storage.fetchAll(AccountModel.self)) ?? []
        let sameTypeAccounts = allAccounts.filter { $0.providerType == providerType && $0.id != accountId }

        // Effective name used both for the duplicate check and the saved account.
        let accountName = (customName?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            ? customName!.trimmingCharacters(in: .whitespaces)
            : name

        switch providerType {
        case .apple:
            guard let issuerID = credsDict["issuerID"], !issuerID.isEmpty,
                  let privateKeyID = credsDict["privateKeyID"], !privateKeyID.isEmpty,
                  let privateKey = credsDict["privateKey"], !privateKey.isEmpty else {
                return String(localized: "Invalid Apple credentials. Required: issuerID, privateKeyID, privateKey.")
            }
            // Same team key may be re-registered under a different name/role.
            // Only block an EXACT duplicate: same private key AND same account name.
            for existing in sameTypeAccounts {
                if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.privateKey == privateKey, existing.name == accountName {
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

        let account = AccountModel(
            id: accountId,
            name: accountName,
            providerType: providerType,
            rules: rules,
            origin: .imported,
            role: role,
            expirationDate: expirationDate
        )

        do {
            try await storage.save(account, id: account.id)
            let wasReimport = uiState.replacingAccountId != nil
            uiState.replacingAccountId = nil
            Log.print.info("[AccountsList] \(wasReimport ? "Re-imported" : "Imported") account: \(accountName)")
            await loadAccounts()
            return nil
        } catch {
            return String(localized: "Failed to save imported account: \(error.localizedDescription)")
        }
    }
}
