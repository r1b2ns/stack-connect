import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol SettingsViewModelProtocol: ObservableObject {
    var uiState: SettingsUiState { get set }
    func deleteAllAccounts() async
    func setPreReviewChecklistEnabled(_ enabled: Bool)
    func setAnalyticsEnabled(_ enabled: Bool)
}

// MARK: - UiState

struct SettingsUiState {
    var appVersion: String = ""
    var buildNumber: String = ""
    var preReviewChecklistEnabled: Bool = true
    var analyticsEnabled: Bool = true
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

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        appSettings: AppSettings = .shared,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        featureFlags: FeatureFlags = .shared
    ) {
        self.featureFlags = featureFlags
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
        self.appSettings = appSettings
        self.analytics = analytics

        let info = Bundle.main.infoDictionary
        uiState.appVersion = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        uiState.buildNumber = info?["CFBundleVersion"] as? String ?? "1"
        uiState.preReviewChecklistEnabled = appSettings.isEnabled(.preReviewChecklistEnabled)
        uiState.analyticsEnabled = analytics.isEnabled
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

    func deleteAllAccounts() async {
        analytics.track(.buttonTap(.confirmDeleteAllAccounts, on: .settings))
        do {
            // Only the accounts the user can see: a hidden store's accounts
            // (Google Play while `googlePlayAccounts` is OFF) are kept.
            let allAccounts = featureFlags.visibleAccounts(try await storage.fetchAll(AccountModel.self))

            // Each account is deleted independently: one failing must not stop the others.
            var failedCount = 0
            for account in allAccounts {
                do {
                    try await AccountCascadeDeleter.delete(account, storage: storage, keychain: keychain)
                } catch {
                    failedCount += 1
                    Log.print.error("[Settings] Failed to delete account \(account.name): \(error.localizedDescription)")
                }
            }

            Log.print.info("[Settings] Deleted all accounts and related data (\(allAccounts.count) accounts)")
            analytics.track(.action(
                .deleteAllAccounts,
                on: .settings,
                result: failedCount == 0 ? .success : .failure,
                parameters: [
                    AnalyticsParameterKey.count: .int(allAccounts.count),
                    AnalyticsParameterKey.failedCount: .int(failedCount)
                ]
            ))
        } catch {
            Log.print.error("[Settings] Failed to delete all accounts: \(error.localizedDescription)")
            analytics.track(.action(.deleteAllAccounts, on: .settings, result: .failure))
        }
    }
}
