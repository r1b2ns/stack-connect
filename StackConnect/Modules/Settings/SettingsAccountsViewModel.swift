import Foundation
import StackProtocols

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

// MARK: - Apple Section

/// The App Store Connect accounts of one connection kind ("API Key" /
/// "Apple ID"), in the list's name order. Only non-empty kinds get one.
struct SettingsAppleAccountsSection: Identifiable, Hashable {
    let connection: AppleConnectionKind
    let accounts: [AccountModel]

    var id: String { connection.rawValue }
}

// MARK: - UiState

struct SettingsAccountsUiState {
    var appleAccounts: [AccountModel] = []
    /// `appleAccounts` split by connection kind, API key accounts first.
    var appleSections: [SettingsAppleAccountsSection] = []
    var firebaseAccounts: [AccountModel] = []
    /// Empty while `googlePlayAccounts` is OFF (stored accounts stay hidden).
    var googlePlayAccounts: [AccountModel] = []
    /// Stores offered by the "Add Account" provider picker.
    var availableProviders: [ProviderType] = FeatureFlags.shared.availableProviders
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
    private let analytics: AnalyticsTracking
    private let featureFlags: FeatureFlags

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        exporter: AccountExporting? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        featureFlags: FeatureFlags = .shared
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.storage = storage
        self.keychain = keychain
        self.exporter = exporter ?? AccountExporter(keychain: keychain)
        self.importer = AccountImporter(storage: storage, keychain: keychain, featureFlags: featureFlags)
        self.analytics = analytics
        self.featureFlags = featureFlags
        uiState.availableProviders = featureFlags.availableProviders
    }

    func loadAccounts() async {
        uiState.isLoading = true
        do {
            // Accounts of a hidden store (Google Play while the flag is OFF)
            // are left out, never deleted.
            var allAccounts = featureFlags.visibleAccounts(try await storage.fetchAll(AccountModel.self))

            // Fill missing rules for legacy accounts
            for i in allAccounts.indices {
                allAccounts[i].fillMissingRules()
            }

            uiState.appleAccounts = allAccounts
                .filter { $0.providerType == .apple }
                .sorted { $0.name < $1.name }
            uiState.appleSections = Self.appleSections(from: uiState.appleAccounts)
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

    /// Splits the (already sorted) Apple accounts by connection kind, keeping
    /// their order inside each section and skipping empty kinds.
    private static func appleSections(from accounts: [AccountModel]) -> [SettingsAppleAccountsSection] {
        AppleConnectionKind.allCases.compactMap { kind in
            let matching = accounts.filter { $0.appleConnectionKind == kind }
            return matching.isEmpty ? nil : SettingsAppleAccountsSection(connection: kind, accounts: matching)
        }
    }

    func updateAccountName(accountId: String, newName: String) async {
        analytics.track(.buttonTap(.save, on: .settingsAccountEdit))
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Find the account in any list
        let allAccounts = uiState.appleAccounts + uiState.firebaseAccounts + uiState.googlePlayAccounts
        guard let existing = allAccounts.first(where: { $0.id == accountId }) else {
            analytics.track(.action(.saveAccount, on: .settingsAccountEdit, result: .failure))
            return
        }

        // `updating` keeps every other field — notably the per-app scope.
        let updated = existing.updating(name: trimmed)

        do {
            try await storage.save(updated, id: updated.id)
            Log.print.info("[SettingsAccounts] Updated account name: \(trimmed)")
            analytics.track(.action(.saveAccount, on: .settingsAccountEdit, result: .success))
            await loadAccounts()
        } catch {
            Log.print.error("[SettingsAccounts] Failed to update account: \(error.localizedDescription)")
            analytics.track(.action(.saveAccount, on: .settingsAccountEdit, result: .failure))
        }
    }

    func deleteAccount(_ account: AccountModel) async {
        analytics.track(.buttonTap(.confirmDelete, on: .settingsAccounts))
        let parameters = [AnalyticsParameterKey.kind: AnalyticsValue.string(account.providerType.rawValue)]
        do {
            try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
            Log.print.info("[SettingsAccounts] Deleted account and related data: \(account.name)")
            analytics.track(.action(.deleteAccount, on: .settingsAccounts, result: .success, parameters: parameters))
            await loadAccounts()
        } catch {
            Log.print.error("[SettingsAccounts] Failed to delete account: \(error.localizedDescription)")
            analytics.track(.action(.deleteAccount, on: .settingsAccounts, result: .failure, parameters: parameters))
        }
    }

    func exportAccountWithRules(account: AccountModel, exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL? {
        let url = makeExportFile(account: account, exportName: exportName, rules: rules, password: password, expirationDate: expirationDate, appsBundles: appsBundles)
        analytics.track(.action(
            .exportAccount,
            on: .exportAccount,
            result: url == nil ? .failure : .success,
            parameters: AnalyticsParameterKey.exportParameters(expirationDate: expirationDate, appsBundles: appsBundles)
        ))
        return url
    }

    private func makeExportFile(account: AccountModel, exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL? {
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
    /// - Returns: the user-facing error, or `nil` on success. The failure event
    ///   carries the error's `error_category`, never its message.
    func importAccount(from url: URL, password: String, customName: String?) async -> String? {
        analytics.track(.buttonTap(.confirmImport, on: .importAccount))
        let error = await performImport(from: url, password: password, customName: customName)
        analytics.track(.action(
            .importAccount,
            on: .importAccount,
            result: error == nil ? .success : .failure,
            parameters: error.map { AnalyticsErrorCategory(importReason: $0.reason).parameters } ?? [:]
        ))
        return error?.message
    }

    private func performImport(from url: URL, password: String, customName: String?) async -> AccountImportError? {
        switch await importer.importAccount(from: url, password: password, customName: customName) {
        case .success(let account):
            Log.print.info("[SettingsAccounts] Imported account: \(account.name) (\(account.providerType.displayName))")
            await loadAccounts()
            return nil // success
        case .failure(let error):
            return error
        }
    }
}
