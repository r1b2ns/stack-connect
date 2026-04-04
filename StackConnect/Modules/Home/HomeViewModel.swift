import Foundation

// MARK: - Protocol

@MainActor
protocol HomeViewModelProtocol: ObservableObject {
    var uiState: HomeUiState { get set }
    func loadPendingReviewApps() async
}

// MARK: - UiState

struct HomeUiState {
    var providers: [ProviderType] = ProviderType.allCases
    var pendingReviewApps: [AppModel] = []
    var isLoadingPending = false
    var accountsMap: [String: AccountModel] = [:]
}

// MARK: - Implementation

@MainActor
final class HomeViewModel: HomeViewModelProtocol {

    @Published var uiState = HomeUiState()

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    func loadPendingReviewApps() async {
        // 0. Load all accounts into map
        do {
            let allAccounts: [AccountModel] = try await storage.fetchAll(AccountModel.self)
            var map: [String: AccountModel] = [:]
            for var account in allAccounts {
                account.fillMissingRules()
                map[account.id] = account
            }
            uiState.accountsMap = map
        } catch {
            Log.print.error("[Home] Failed to load accounts: \(error.localizedDescription)")
        }

        // 1. Load from SwiftData first (instant)
        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            let pending = allApps.filter { $0.hasReviewPending && !$0.isArchived }
            uiState.pendingReviewApps = pending.sorted { ($0.name) < ($1.name) }
        } catch {
            Log.print.error("[Home] Failed to load pending review apps: \(error.localizedDescription)")
        }

        guard !uiState.pendingReviewApps.isEmpty else { return }

        // 2. Refresh status from API for each pending app
        uiState.isLoadingPending = true

        var updatedApps: [AppModel] = []

        for app in uiState.pendingReviewApps {
            guard let credentials: AppleCredentials = keychain.object(forKey: "credentials.\(app.accountId)") else {
                updatedApps.append(app)
                continue
            }

            let connection = AppleAccountConnection(credentials: credentials)
            let state = await connection.fetchAppStoreVersion(appId: app.id)

            var updated = app
            if let s = state.state {
                updated.appStoreState = AppStoreState(rawValue: s)
            }
            if let v = state.version {
                updated.versionString = v
            }
            updated.hasReviewPending = updated.appStoreState?.isReviewPending ?? false

            // Persist updated status
            do {
                try await storage.save(updated, id: "\(app.accountId).\(app.id)")
            } catch {
                Log.print.error("[Home] Failed to save updated status for \(app.name): \(error.localizedDescription)")
            }

            if updated.hasReviewPending {
                updatedApps.append(updated)
            }
        }

        uiState.pendingReviewApps = updatedApps.sorted { $0.name < $1.name }
        uiState.isLoadingPending = false

        Log.print.info("[Home] Refreshed \(updatedApps.count) pending review apps")
    }
}
