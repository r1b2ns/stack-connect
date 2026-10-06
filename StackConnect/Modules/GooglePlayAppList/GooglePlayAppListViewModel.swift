import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol GooglePlayAppListViewModelProtocol: ObservableObject {
    var uiState: GooglePlayAppListUiState { get set }
    func load() async
    func addApp(packageName: String) async
    func removeApp(_ app: GooglePlayAppItem) async
}

// MARK: - UiState

struct GooglePlayAppListUiState {
    var account: AccountModel
    var apps: [GooglePlayAppItem] = []
    var isLoading = false
    var isSyncing = false
    var showSyncToast = false
    /// Last load/sync failure, already user-facing. Shown full screen when there is
    /// nothing cached, or as an inline banner above the cached list.
    var error: String?
    var showAddApp = false
    var isAdding = false
    var addError: String?
    var toastMessage: ToastMessage?
}

// MARK: - Implementation

@MainActor
final class GooglePlayAppListViewModel: GooglePlayAppListViewModelProtocol {

    /// Builds the Rust-core connection for the stored credentials. Injected so
    /// tests never touch the network or the core.
    typealias ConnectionFactory = (GooglePlayCredentials) -> any GooglePlayAccountConnecting

    /// Builds the manual-add access check (still native, plan D5). Injected for tests.
    typealias AccessCheckerFactory = (GooglePlayCredentials) -> any GooglePlayAppAccessChecking

    @Published var uiState: GooglePlayAppListUiState

    private let keychain: KeyStorable
    private let storage: PersistentStorable
    private let connectionFactory: ConnectionFactory
    private let accessCheckerFactory: AccessCheckerFactory

    init(
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil,
        connectionFactory: @escaping ConnectionFactory = { GooglePlayAccountConnection(credentials: $0) },
        accessCheckerFactory: @escaping AccessCheckerFactory = { GooglePlayEditsAccessChecker(credentials: $0) }
    ) {
        self.uiState = GooglePlayAppListUiState(account: account)
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
        self.connectionFactory = connectionFactory
        self.accessCheckerFactory = accessCheckerFactory
    }

    // MARK: - Load

    /// Offline-first: shows the cached list right away, then syncs it from the
    /// Play Developer Reporting API (via the Rust core) and persists the result.
    /// A failed sync keeps whatever is on screen.
    func load() async {
        uiState.error = nil

        // 1. Cached list first (offline-first).
        if let cached = await loadFromStorage(), !cached.isEmpty {
            uiState.apps = Self.sorted(cached)
        }
        uiState.isLoading = uiState.apps.isEmpty

        guard let credentials = storedCredentials() else {
            Log.print.error("[GooglePlayAppList] No credentials found for account: \(self.uiState.account.name)")
            uiState.error = String(localized: "No credentials found for this account.")
            uiState.isLoading = false
            return
        }

        // 2. Sync from the API.
        uiState.isSyncing = true
        if !uiState.apps.isEmpty {
            uiState.showSyncToast = true
        }

        do {
            let remoteApps = try await connectionFactory(credentials).fetchApps()
            uiState.apps = Self.merge(remote: remoteApps, into: uiState.apps)
            await saveToStorage()
            Log.print.info("[GooglePlayAppList] Synced \(remoteApps.count) apps for account: \(self.uiState.account.name)")
        } catch {
            Log.print.error("[GooglePlayAppList] Sync failed: \(error.localizedDescription)")
            // Offline with a cached list: the global offline banner already says
            // so — keep the list without a second warning.
            if !(GooglePlayErrorTranslator.isOffline(error) && !uiState.apps.isEmpty) {
                uiState.error = GooglePlayErrorTranslator.friendlyMessage(for: error)
            }
        }

        uiState.isLoading = false
        uiState.isSyncing = false
    }

    // MARK: - Add App Manually

    func addApp(packageName: String) async {
        let trimmed = packageName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !uiState.apps.contains(where: { $0.packageName == trimmed }) else {
            uiState.addError = String(localized: "This app is already in the list.")
            return
        }

        guard let credentials = storedCredentials() else {
            uiState.addError = String(localized: "No credentials found.")
            return
        }

        uiState.isAdding = true
        uiState.addError = nil

        do {
            try await accessCheckerFactory(credentials).verifyAccess(packageName: trimmed)

            let item = GooglePlayAppItem(
                id: trimmed,
                packageName: trimmed,
                title: nil,
                isManuallyAdded: true
            )
            uiState.apps = Self.sorted(uiState.apps + [item])
            await saveToStorage()

            uiState.showAddApp = false
            uiState.toastMessage = ToastMessage(String(localized: "App added"), icon: "checkmark.circle.fill")
            Log.print.info("[GooglePlayAppList] Manually added: \(trimmed)")
        } catch {
            uiState.addError = GooglePlayErrorTranslator.friendlyMessage(for: error)
            Log.print.error("[GooglePlayAppList] Add failed: \(error.localizedDescription)")
        }

        uiState.isAdding = false
    }

    // MARK: - Remove

    func removeApp(_ app: GooglePlayAppItem) async {
        uiState.apps.removeAll { $0.id == app.id }
        await saveToStorage()
    }

    // MARK: - Merge

    /// API apps are the source of truth; manually added apps the API doesn't
    /// return are kept. Deduped by package name — when the API starts returning a
    /// manually added app, the API entry (with its display name) wins.
    static func merge(
        remote: [StackProtocols.AppInfo],
        into current: [GooglePlayAppItem]
    ) -> [GooglePlayAppItem] {
        var seen = Set<String>()
        var merged: [GooglePlayAppItem] = []

        for app in remote where seen.insert(app.bundleId).inserted {
            merged.append(GooglePlayAppItem(
                id: app.bundleId,
                packageName: app.bundleId,
                title: app.name.isEmpty ? nil : app.name,
                isManuallyAdded: false
            ))
        }

        for app in current where app.isManuallyAdded && seen.insert(app.packageName).inserted {
            merged.append(app)
        }

        return sorted(merged)
    }

    // MARK: - Private

    private var storageKey: String {
        GooglePlayAppItem.cacheKey(accountId: uiState.account.id)
    }

    private static func sorted(_ apps: [GooglePlayAppItem]) -> [GooglePlayAppItem] {
        apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func storedCredentials() -> GooglePlayCredentials? {
        keychain.object(forKey: "credentials.\(uiState.account.id)")
    }

    private func loadFromStorage() async -> [GooglePlayAppItem]? {
        do {
            return try await storage.fetch([GooglePlayAppItem].self, id: storageKey)
        } catch {
            Log.print.error("[GooglePlayAppList] Storage load failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Persists the whole list (API + manual apps) so the next launch can render
    /// it offline. `isManuallyAdded` keeps manual apps distinguishable on merge.
    private func saveToStorage() async {
        do {
            try await storage.save(uiState.apps, id: storageKey)
        } catch {
            Log.print.error("[GooglePlayAppList] Storage save failed: \(error.localizedDescription)")
        }
    }
}
