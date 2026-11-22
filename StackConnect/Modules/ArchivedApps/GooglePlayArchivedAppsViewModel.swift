import Foundation
import StackProtocols

// MARK: - Protocol

@MainActor
protocol GooglePlayArchivedAppsViewModelProtocol: ObservableObject {
    var uiState: GooglePlayArchivedAppsUiState { get set }
    func loadApps() async
    func refresh() async
    func unarchive(app: GooglePlayAppItem) async
}

// MARK: - UiState

struct GooglePlayArchivedAppsUiState {
    var account: AccountModel
    /// The account's archived apps, inside its per-app scope.
    var apps: [GooglePlayAppItem] = []
    var isLoading = false
    var searchQuery = ""
    var toastMessage: ToastMessage?

    /// `apps` narrowed by `searchQuery` (name or package, case-insensitive).
    var filteredApps: [GooglePlayAppItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.packageName.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Implementation

/// Archived apps of a Google Play account: the Play counterpart of
/// `ArchivedAppsViewModel`. Play apps live in one cached list per account
/// (`GooglePlayAppItem.cacheKey`), so this screen reads and edits that list —
/// no network: the Play list screen and the background sync keep it fresh.
@MainActor
final class GooglePlayArchivedAppsViewModel: GooglePlayArchivedAppsViewModelProtocol {

    @Published var uiState: GooglePlayArchivedAppsUiState

    private let storage: PersistentStorable
    private let analytics: AnalyticsTracking
    /// Rewrites the WidgetKit snapshot after an unarchive (see
    /// `GooglePlayAppListViewModel`). Injected for tests.
    private let dashboardDidChange: @MainActor (PersistentStorable) async -> Void

    init(
        account: AccountModel,
        storage: PersistentStorable? = nil,
        analytics: AnalyticsTracking = AnalyticsService.shared,
        dashboardDidChange: @escaping @MainActor (PersistentStorable) async -> Void = { await WidgetDashboardSnapshotWriter.write(storage: $0) }
    ) {
        self.uiState = GooglePlayArchivedAppsUiState(account: account)
        self.storage = storage ?? SwiftDataStorable.shared
        self.analytics = analytics
        self.dashboardDidChange = dashboardDidChange
    }

    func loadApps() async {
        _ = await reload()
    }

    /// Pull-to-refresh: re-reads the cached list, tracked as a `refresh`
    /// action with its outcome.
    func refresh() async {
        let loaded = await reload()
        analytics.track(.action(.refresh, on: .googlePlayArchivedApps, result: loaded ? .success : .failure))
    }

    /// Returns `true` when the cached list could be read (none cached yet
    /// counts as read: nothing is archived).
    private func reload() async -> Bool {
        uiState.isLoading = uiState.apps.isEmpty
        defer { uiState.isLoading = false }
        do {
            let all = try await storage.fetch([GooglePlayAppItem].self, id: storageKey) ?? []
            uiState.apps = GooglePlayAppListSync.sorted(all.filter { $0.isArchived && isInScope($0) })
            return true
        } catch {
            Log.print.error("[GooglePlayArchivedApps] Failed to load apps: \(error.localizedDescription)")
            return false
        }
    }

    /// Clears the app's `isArchived` in the stored list (read fresh, so an
    /// app list sync that ran meanwhile is never overwritten) and drops it
    /// from this screen.
    func unarchive(app: GooglePlayAppItem) async {
        analytics.track(.buttonTap(.unarchive, on: .googlePlayArchivedApps))
        let parameters = [AnalyticsParameterKey.enabled: AnalyticsValue.bool(false)]

        do {
            var all = try await storage.fetch([GooglePlayAppItem].self, id: storageKey) ?? []
            guard let index = all.firstIndex(where: { $0.packageName == app.packageName }) else {
                // No longer in the list (removed meanwhile): nothing to unarchive.
                uiState.apps.removeAll { $0.packageName == app.packageName }
                return
            }
            all[index].isArchived = false
            try await storage.save(all, id: storageKey)
            await dashboardDidChange(storage)
            uiState.apps.removeAll { $0.packageName == app.packageName }
            uiState.toastMessage = ToastMessage(String(localized: "App unarchived"), icon: "archivebox.fill")
            Log.print.info("[GooglePlayArchivedApps] Unarchived \(app.packageName)")
            analytics.track(.action(.toggleArchive, on: .googlePlayArchivedApps, result: .success, parameters: parameters))
        } catch {
            Log.print.error("[GooglePlayArchivedApps] Unarchive failed: \(error.localizedDescription)")
            analytics.track(.action(.toggleArchive, on: .googlePlayArchivedApps, result: .failure, parameters: parameters))
        }
    }

    // MARK: - Private

    private var storageKey: String {
        GooglePlayAppItem.cacheKey(accountId: uiState.account.id)
    }

    private func isInScope(_ app: GooglePlayAppItem) -> Bool {
        uiState.account.allowsApp(bundleId: app.packageName)
    }
}
