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
    private let importer: AccountImporter

    init(
        providerType: ProviderType,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.uiState = AccountsListUiState(providerType: providerType)
        self.storage = storage
        self.keychain = keychain
        self.importer = AccountImporter(storage: storage, keychain: keychain)
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

    /// Removes an account along with its apps, versions, reply templates and
    /// keychain credentials (see `AccountCascadeDeleter`).
    private func cascadeDelete(_ account: AccountModel) async {
        do {
            try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
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

    /// Only accepts files of this list's provider. A pending re-import replaces
    /// that account in place (see `AccountImporter.Options`).
    func importAccount(from url: URL, password: String, customName: String?) async -> String? {
        let options = AccountImporter.Options(
            expectedProvider: uiState.providerType,
            replacingAccountId: uiState.replacingAccountId
        )

        switch await importer.importAccount(from: url, password: password, customName: customName, options: options) {
        case .success(let account):
            let wasReimport = uiState.replacingAccountId != nil
            uiState.replacingAccountId = nil
            Log.print.info("[AccountsList] \(wasReimport ? "Re-imported" : "Imported") account: \(account.name)")
            await loadAccounts()
            return nil
        case .failure(let error):
            return error.message
        }
    }
}
