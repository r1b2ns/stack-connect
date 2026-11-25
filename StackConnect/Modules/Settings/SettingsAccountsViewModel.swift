import Combine
import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol SettingsAccountsViewModelProtocol: ObservableObject {
    var uiState: SettingsAccountsUiState { get set }
    func loadAccounts() async
    func clearSearch()
    /// "Delete all accounts" confirmed: every visible account, with its data.
    func deleteAllAccounts() async
}

// MARK: - UiState

struct SettingsAccountsUiState {
    /// The groups (App Store Connect, Google Play only while
    /// `googlePlayAccounts` is ON, Firebase), the search and the statuses.
    var listing = AccountsListingState()
    var showDeleteAllConfirmation = false
}

// MARK: - Implementation

/// Settings › Accounts (plan `unified-accounts.md` §4): search, add or import
/// an account, a per-store "Add", rows that open the account, and "Delete all
/// accounts" at the bottom.
@MainActor
final class SettingsAccountsViewModel: SettingsAccountsViewModelProtocol {

    @Published var uiState = SettingsAccountsUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable
    private let analytics: AnalyticsTracking
    private let featureFlags: FeatureFlags
    private let statusProvider: AccountStatusProviding
    private var cancellables = Set<AnyCancellable>()

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        featureFlags: FeatureFlags = .shared,
        statusProvider: AccountStatusProviding? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        let storage: PersistentStorable = storage ?? SwiftDataStorable.shared
        self.storage = storage
        self.keychain = keychain
        self.analytics = analytics
        self.featureFlags = featureFlags
        self.statusProvider = statusProvider ?? AccountStatusService(storage: storage, keychain: keychain)

        // A sign-in expired or works again, a sync flagged/cleared agreements,
        // or the wizard / the detail added or removed accounts.
        self.statusProvider.changes
            .merge(with: notificationCenter.publisher(for: .accountsDidChange).map { _ in () }.receive(on: DispatchQueue.main))
            .sink { [weak self] in
                Task { await self?.loadAccounts() }
            }
            .store(in: &cancellables)
    }

    func loadAccounts() async {
        uiState.listing.isLoading = true
        defer {
            uiState.listing.isLoading = false
            uiState.listing.hasLoaded = true
        }
        do {
            uiState.listing.apply(try await AccountsListingSnapshot.load(storage: storage, featureFlags: featureFlags, statusProvider: statusProvider))
        } catch {
            Log.print.error("[SettingsAccounts] Failed to load accounts: \(error.localizedDescription)")
        }
    }

    func clearSearch() {
        uiState.listing.query = ""
    }

    func deleteAllAccounts() async {
        analytics.track(.buttonTap(.confirmDeleteAllAccounts, on: .settingsAccounts))
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
                    Log.print.error("[SettingsAccounts] Failed to delete account \(account.name): \(error.localizedDescription)")
                }
            }

            Log.print.info("[SettingsAccounts] Deleted all accounts and related data (\(allAccounts.count) accounts)")
            analytics.track(.action(
                .deleteAllAccounts,
                on: .settingsAccounts,
                result: failedCount == 0 ? .success : .failure,
                parameters: [
                    AnalyticsParameterKey.count: .int(allAccounts.count),
                    AnalyticsParameterKey.failedCount: .int(failedCount)
                ]
            ))
        } catch {
            Log.print.error("[SettingsAccounts] Failed to delete all accounts: \(error.localizedDescription)")
            analytics.track(.action(.deleteAllAccounts, on: .settingsAccounts, result: .failure))
        }
        await loadAccounts()
    }
}
