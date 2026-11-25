import Combine
import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol SettingsAccountDetailViewModelProtocol: ObservableObject {
    var uiState: SettingsAccountDetailUiState { get set }
    /// Re-reads the account and its status (edits made in Account Settings,
    /// a reconnect that worked).
    func load() async
    /// - Returns: whether the account is gone.
    func deleteAccount() async -> Bool
    func exportAccountWithRules(exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL?
    func appsForExport() async -> [ExportableApp]
}

// MARK: - UiState

struct SettingsAccountDetailUiState {
    var account: AccountModel
    /// `nil` when the account works (connected).
    var status: AccountStatus?
    /// "Sign in again" (Apple ID session, Google login) or "Re-import File"
    /// (expired shared account): the wizard's `.reconnect` can fix it here.
    var reconnectMethod: AccountWizardMethod?
    var showDeleteConfirmation = false
    var shareItem: ShareableFileURL?

    /// Why Export is off, or `nil` when the account can be exported.
    var exportUnavailableReason: String? {
        Self.exportUnavailableReason(for: account)
    }

    static func exportUnavailableReason(for account: AccountModel) -> String? {
        guard !account.isExportable else { return nil }
        if let reason = account.exportUnavailableReason { return reason }
        if account.authMethod == .googleSignIn {
            return String(localized: "Accounts added with a Google account can't be exported: the sign-in is your personal Google login. Share a service account key instead.",
                          comment: "Account detail: why a Google sign-in account has no export.")
        }
        if account.origin == .imported {
            return String(localized: "Accounts imported from a file can't be exported again.",
                          comment: "Account detail: why an imported account has no export.")
        }
        return String(localized: "\(account.providerType.displayName) accounts can't be exported.",
                      comment: "Account detail: why the account's store has no export. The placeholder is the store, e.g. Firebase.")
    }
}

// MARK: - Implementation

/// Settings › Accounts › an account (plan `unified-accounts.md` §4): its
/// status, "Sign in again" when its sign-in is disconnected, its details,
/// Export (off with why when it can't be exported) and Delete.
@MainActor
final class SettingsAccountDetailViewModel: SettingsAccountDetailViewModelProtocol {

    @Published var uiState: SettingsAccountDetailUiState

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let exporter: AccountExporting
    private let analytics: AnalyticsTracking
    private let statusProvider: AccountStatusProviding
    private var cancellables = Set<AnyCancellable>()

    init(
        account: AccountModel,
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        exporter: AccountExporting? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        statusProvider: AccountStatusProviding? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.uiState = SettingsAccountDetailUiState(account: account)
        self.storage = storage
        self.keychain = keychain
        self.exporter = exporter ?? AccountExporter(keychain: keychain)
        self.analytics = analytics
        self.statusProvider = statusProvider ?? AccountStatusService(storage: storage, keychain: keychain)
        refreshStatus()

        self.statusProvider.changes
            .merge(with: notificationCenter.publisher(for: .accountsDidChange).map { _ in () }.receive(on: DispatchQueue.main))
            .sink { [weak self] in
                Task { await self?.load() }
            }
            .store(in: &cancellables)
    }

    func load() async {
        if var stored: AccountModel = try? await storage.fetch(AccountModel.self, id: uiState.account.id) {
            stored.fillMissingRules()
            uiState.account = stored
        }
        refreshStatus()
    }

    private func refreshStatus() {
        uiState.status = statusProvider.statuses(for: [uiState.account])[uiState.account.id]
        uiState.reconnectMethod = Self.reconnectMethod(for: uiState.account, status: uiState.status, keychain: keychain)
    }

    /// The way to fix a disconnected account from here, or `nil`: a sign-in
    /// that expired (and whose session or login is still on the device), or
    /// a shared file that expired.
    static func reconnectMethod(for account: AccountModel, status: AccountStatus?, keychain: KeyStorable) -> AccountWizardMethod? {
        guard let status, let method = AccountWizardConfig.reconnectMethod(for: account) else { return nil }
        switch method {
        case .appleIdSignIn:
            guard status.issues.contains(.signInExpired),
                  AppleSessionReferences.reference(of: account, keychain: keychain) != nil else { return nil }
        case .googleSignIn:
            guard status.issues.contains(.signInExpired),
                  GoogleLoginReferences.loginId(of: account, keychain: keychain) != nil else { return nil }
        case .scexportFile:
            guard status.issues.contains(.accessExpired) else { return nil }
        case .apiKey, .serviceAccount:
            return nil
        }
        return method
    }

    func deleteAccount() async -> Bool {
        analytics.track(.buttonTap(.confirmDelete, on: .accountDetail))
        let account = uiState.account
        let parameters = [AnalyticsParameterKey.kind: AnalyticsValue.string(account.providerType.rawValue)]
        do {
            try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
            Log.print.info("[AccountDetail] Deleted account and related data: \(account.name)")
            analytics.track(.action(.deleteAccount, on: .accountDetail, result: .success, parameters: parameters))
            return true
        } catch {
            Log.print.error("[AccountDetail] Failed to delete account: \(error.localizedDescription)")
            analytics.track(.action(.deleteAccount, on: .accountDetail, result: .failure, parameters: parameters))
            return false
        }
    }

    func exportAccountWithRules(exportName: String, rules: AccountRules, password: String, expirationDate: Date?, appsBundles: [String]?) -> URL? {
        guard uiState.account.isExportable else { return nil }
        let url: URL?
        do {
            url = try exporter.export(AccountExportRequest(
                account: uiState.account,
                exportName: exportName,
                rules: rules,
                password: password,
                expirationDate: expirationDate,
                appsBundles: appsBundles
            ))
        } catch {
            Log.print.error("[AccountDetail] Export failed: \(String(describing: error))")
            url = nil
        }
        analytics.track(.action(
            .exportAccount,
            on: .exportAccount,
            result: url == nil ? .failure : .success,
            parameters: AnalyticsParameterKey.exportParameters(expirationDate: expirationDate, appsBundles: appsBundles)
        ))
        return url
    }

    /// Apps of the account, sorted by name, for the export scope picker.
    func appsForExport() async -> [ExportableApp] {
        await ExportableAppsLoader.apps(for: uiState.account, storage: storage)
    }
}
