import Foundation

// MARK: - Protocol

@MainActor
protocol SettingsViewModelProtocol: ObservableObject {
    var uiState: SettingsUiState { get set }
    func deleteAllAccounts() async
    func setPreReviewChecklistEnabled(_ enabled: Bool)
}

// MARK: - UiState

struct SettingsUiState {
    var appVersion: String = ""
    var buildNumber: String = ""
    var preReviewChecklistEnabled: Bool = true
}

// MARK: - Implementation

@MainActor
final class SettingsViewModel: SettingsViewModelProtocol {

    @Published var uiState = SettingsUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let appSettings: AppSettings

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        appSettings: AppSettings = .shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.appSettings = appSettings

        let info = Bundle.main.infoDictionary
        uiState.appVersion = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        uiState.buildNumber = info?["CFBundleVersion"] as? String ?? "1"
        uiState.preReviewChecklistEnabled = appSettings.isEnabled(.preReviewChecklistEnabled)
    }

    func setPreReviewChecklistEnabled(_ enabled: Bool) {
        uiState.preReviewChecklistEnabled = enabled
        appSettings.setEnabled(enabled, for: .preReviewChecklistEnabled)
        Log.print.info("[Settings] Pre-review checklist enabled: \(enabled)")
    }

    func deleteAllAccounts() async {
        do {
            let allAccounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)

            // Each account is deleted independently: one failing must not stop the others.
            for account in allAccounts {
                do {
                    try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
                } catch {
                    Log.print.error("[Settings] Failed to delete account \(account.name): \(error.localizedDescription)")
                }
            }

            Log.print.info("[Settings] Deleted all accounts and related data (\(allAccounts.count) accounts)")
        } catch {
            Log.print.error("[Settings] Failed to delete all accounts: \(error.localizedDescription)")
        }
    }
}
