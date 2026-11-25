import Combine
import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol SettingsViewModelProtocol: ObservableObject {
    var uiState: SettingsUiState { get set }
    /// The "Summary" of the Accounts row (total, needing attention, per store).
    func loadAccountsSummary() async
    func setPreReviewChecklistEnabled(_ enabled: Bool)
    func setAnalyticsEnabled(_ enabled: Bool)
}

// MARK: - UiState

struct SettingsUiState {
    var appVersion: String = ""
    var buildNumber: String = ""
    var preReviewChecklistEnabled: Bool = true
    var analyticsEnabled: Bool = true
    /// Settings › Privacy › Audit (flag `networkAudit`).
    var showsNetworkAudit: Bool = false
    /// The Accounts row (Summary style). Visible accounts only.
    var accountsSummary: AccountsSummary = .empty
}

// MARK: - Implementation

@MainActor
final class SettingsViewModel: SettingsViewModelProtocol {

    @Published var uiState = SettingsUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let appSettings: AppSettings
    private let analytics: AnalyticsTracking
    private let featureFlags: FeatureFlags
    private let statusProvider: AccountStatusProviding
    private var cancellables = Set<AnyCancellable>()

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        appSettings: AppSettings = .shared,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        featureFlags: FeatureFlags = .shared,
        statusProvider: AccountStatusProviding? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.featureFlags = featureFlags
        self.storage = storage
        self.keychain = keychain
        self.appSettings = appSettings
        self.analytics = analytics
        self.statusProvider = statusProvider ?? AccountStatusService(storage: storage, keychain: keychain)

        let info = Bundle.main.infoDictionary
        uiState.appVersion = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        uiState.buildNumber = info?["CFBundleVersion"] as? String ?? "1"
        uiState.preReviewChecklistEnabled = appSettings.isEnabled(.preReviewChecklistEnabled)
        uiState.analyticsEnabled = analytics.isEnabled
        uiState.showsNetworkAudit = featureFlags.isEnabled(.networkAudit)

        // Accounts added, imported or deleted, or a status changed.
        self.statusProvider.changes
            .merge(with: notificationCenter.publisher(for: .accountsDidChange).map { _ in () }.receive(on: DispatchQueue.main))
            .sink { [weak self] in
                Task { await self?.loadAccountsSummary() }
            }
            .store(in: &cancellables)
    }

    func loadAccountsSummary() async {
        do {
            let accounts = featureFlags.visibleAccounts(try await storage.fetchAll(AccountModel.self))
            uiState.accountsSummary = AccountsSummary(
                accounts: accounts,
                statuses: statusProvider.statuses(for: accounts),
                providers: featureFlags.availableProviders
            )
        } catch {
            Log.print.error("[Settings] Failed to load the accounts summary: \(error.localizedDescription)")
        }
    }

    func setPreReviewChecklistEnabled(_ enabled: Bool) {
        uiState.preReviewChecklistEnabled = enabled
        appSettings.setEnabled(enabled, for: .preReviewChecklistEnabled)
        analytics.track(.action(
            .togglePreReviewChecklist,
            on: .settings,
            parameters: [AnalyticsParameterKey.enabled: .bool(enabled)]
        ))
        Log.print.info("[Settings] Pre-review checklist enabled: \(enabled)")
    }

    /// Delegates to the tracker, which owns the setting and the opt-out
    /// "last event"; the ViewModel never writes `AppSetting.analyticsEnabled`.
    func setAnalyticsEnabled(_ enabled: Bool) {
        analytics.setEnabled(enabled)
        uiState.analyticsEnabled = analytics.isEnabled
        Log.print.info("[Settings] Usage analytics enabled: \(enabled)")
    }
}
