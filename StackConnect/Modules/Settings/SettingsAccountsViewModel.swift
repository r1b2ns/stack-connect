import Foundation

// MARK: - Protocol

@MainActor
protocol SettingsAccountsViewModelProtocol: ObservableObject {
    var uiState: SettingsAccountsUiState { get set }
    func loadAccounts() async
    func updateAccountName(accountId: String, newName: String) async
    func deleteAccount(_ account: AccountModel) async
    func exportAccountData(account: AccountModel) -> String?
    func exportAccountFile(account: AccountModel) -> URL?
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
            try await storage.delete(AccountModel.self, id: account.id)
            keychain.removeObject(forKey: "credentials.\(account.id)")
            Log.print.info("[SettingsAccounts] Deleted account: \(account.name)")
            await loadAccounts()
        } catch {
            Log.print.error("[SettingsAccounts] Failed to delete account: \(error.localizedDescription)")
        }
    }

    func exportAccountData(account: AccountModel) -> String? {
        var exportDict: [String: Any] = [
            "id": account.id,
            "name": account.name,
            "providerType": account.providerType.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: account.createdAt)
        ]

        // Include rules
        let rules = account.rules
        exportDict["rules"] = [
            "apps": rules.apps.map(\.rawValue),
            "version": rules.version.map(\.rawValue),
            "users": rules.users.map(\.rawValue),
            "review": rules.review.map(\.rawValue),
            "testFlight": rules.testFlight.map(\.rawValue),
            "analytics": rules.analytics.map(\.rawValue)
        ]

        // Include credentials based on provider type
        switch account.providerType {
        case .apple:
            if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(account.id)") {
                exportDict["credentials"] = [
                    "issuerID": creds.issuerID,
                    "privateKeyID": creds.privateKeyID,
                    "privateKey": creds.privateKey
                ]
            }
        case .firebase:
            if let creds: FirebaseCredentials = keychain.object(forKey: "credentials.\(account.id)") {
                exportDict["credentials"] = [
                    "serviceAccountJSON": creds.serviceAccountJSON
                ]
            }
        case .googlePlay:
            if let creds: GooglePlayCredentials = keychain.object(forKey: "credentials.\(account.id)") {
                exportDict["credentials"] = [
                    "serviceAccountJSON": creds.serviceAccountJSON
                ]
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
    }

    func exportAccountFile(account: AccountModel) -> URL? {
        guard let json = exportAccountData(account: account) else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let sanitizedName = account.name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(sanitizedName)-stackconnect-\(dateString).json"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try json.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            Log.print.error("[SettingsAccounts] Failed to write export file: \(error.localizedDescription)")
            return nil
        }
    }
}
