import Foundation

// MARK: - Protocol

@MainActor
protocol SettingsAccountsViewModelProtocol: ObservableObject {
    var uiState: SettingsAccountsUiState { get set }
    func loadAccounts() async
    func updateAccountName(accountId: String, newName: String) async
    func deleteAccount(_ account: AccountModel) async
    func exportAccountWithRules(account: AccountModel, exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL?
    func appsForExport(account: AccountModel) async -> [ExportableApp]
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
    var shareItem: ShareableFileURL?
}

// MARK: - Implementation

@MainActor
final class SettingsAccountsViewModel: SettingsAccountsViewModelProtocol {

    @Published var uiState = SettingsAccountsUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let exporter: AccountExporting
    private let importer: AccountImporter

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        exporter: AccountExporting? = nil
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.storage = storage
        self.keychain = keychain
        self.exporter = exporter ?? AccountExporter(keychain: keychain)
        self.importer = AccountImporter(storage: storage, keychain: keychain)
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

        // `updating` keeps every other field — notably the per-app scope.
        let updated = existing.updating(name: trimmed)

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
            try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
            Log.print.info("[SettingsAccounts] Deleted account and related data: \(account.name)")
            await loadAccounts()
        } catch {
            Log.print.error("[SettingsAccounts] Failed to delete account: \(error.localizedDescription)")
        }
    }

    func exportAccountWithRules(account: AccountModel, exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL? {
        do {
            return try exporter.export(AccountExportRequest(
                account: account,
                exportName: exportName,
                rules: rules,
                password: password,
                expirationDate: expirationDate,
                appsBundles: appsBundles
            ))
        } catch {
            Log.print.error("[SettingsAccounts] Export failed: \(String(describing: error))")
            return nil
        }
    }

    /// Apps of the given account, sorted by name, for the export scope picker.
    func appsForExport(account: AccountModel) async -> [ExportableApp] {
        await ExportableAppsLoader.apps(for: account, storage: storage)
    }

    // MARK: - Import

    /// Accepts a `.scexport` file of any provider (see `AccountImporter`).
    func importAccount(from url: URL, password: String, customName: String?) async -> String? {
        switch await importer.importAccount(from: url, password: password, customName: customName) {
        case .success(let account):
            Log.print.info("[SettingsAccounts] Imported account: \(account.name) (\(account.providerType.displayName))")
            await loadAccounts()
            return nil // success
        case .failure(let error):
            return error.message
        }
    }
}
