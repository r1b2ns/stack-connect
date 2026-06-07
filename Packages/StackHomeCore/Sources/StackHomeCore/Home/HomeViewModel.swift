import Foundation
import StackProtocols

// MARK: - UI State

/// Foundation-pure state for the Home dashboard, shared by iOS and the Windows
/// port. Carries no SwiftUI/Combine types (US-010 AC-4): the iOS app republishes
/// it through a thin `ObservableObject` adapter.
public struct HomeUiState {
    /// Providers shown as account cards. Google Play is intentionally excluded
    /// from the Home grid (matching the iOS baseline).
    public var providers: [ProviderType]
    public var widgets: [any HomeWidget]
    public var isLoading: Bool
    public var syncState: SyncState
    public var expiredAccount: AccountModel?
    public var showExpiredAlert: Bool
    public var expiringSoonAccount: AccountModel?
    public var showExpiringSoonAlert: Bool

    public init(
        providers: [ProviderType] = ProviderType.allCases.filter { $0 != .googlePlay },
        widgets: [any HomeWidget] = [],
        isLoading: Bool = false,
        syncState: SyncState = SyncState(),
        expiredAccount: AccountModel? = nil,
        showExpiredAlert: Bool = false,
        expiringSoonAccount: AccountModel? = nil,
        showExpiringSoonAlert: Bool = false
    ) {
        self.providers = providers
        self.widgets = widgets
        self.isLoading = isLoading
        self.syncState = syncState
        self.expiredAccount = expiredAccount
        self.showExpiredAlert = showExpiredAlert
        self.expiringSoonAccount = expiringSoonAccount
        self.showExpiringSoonAlert = showExpiringSoonAlert
    }
}

// MARK: - View Model

/// Foundation-pure Home view model shared by iOS and the Windows port (T-A10).
///
/// Owns the Home dashboard's state shaping, manual + automatic sync
/// orchestration, account-expiration precedence (Expired before Expiring —
/// US-005 AC-7), widget add/remove/reorder (US-008), and widget-configuration
/// load+save via `KeyStorable` under `home.widget.configurations` (US-010 AC-6).
///
/// Like `SyncService`, this type is **not** an `ObservableObject` and uses no
/// Combine API unconditionally (US-010 AC-4). State changes are surfaced via:
/// - `state`: the latest snapshot (synchronous read).
/// - `onStateChanged`: a callback fired on every change (MainActor).
/// - `states`: an `AsyncStream<HomeUiState>` replaying the current value then
///   yielding every subsequent change.
///
/// The iOS app wraps this in a thin `#if canImport(Combine)` `ObservableObject`
/// adapter (`HomeViewModel` in the app target) that republishes `state` via
/// `@Published uiState` so the existing SwiftUI Home view/coordinator keep
/// observing unchanged.
///
/// Widget instances are created through an injected `widgetFactory` so core
/// never references a platform widget registry: iOS supplies its observable
/// widget adapters, Windows supplies SwiftCrossUI-backed ones; both conform to
/// the Foundation-pure `HomeWidget` protocol.
@MainActor
public final class HomeViewModel {

    /// Storage key for the persisted widget configuration list (US-010 AC-6).
    public static let widgetsStorageKey = "home.widget.configurations"

    // MARK: State exposure

    public private(set) var state: HomeUiState {
        didSet {
            onStateChanged?(state)
            for continuation in continuations.values { continuation.yield(state) }
        }
    }

    /// Fired on the MainActor whenever `state` changes.
    public var onStateChanged: ((HomeUiState) -> Void)?

    /// An `AsyncStream` that immediately replays the current `state`, then yields
    /// every subsequent change. Each access returns an independent stream.
    public var states: AsyncStream<HomeUiState> {
        AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            let id = UUID()
            self.continuations[id] = continuation
            continuation.yield(self.state)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    private var continuations: [UUID: AsyncStream<HomeUiState>.Continuation] = [:]

    // MARK: Dependencies

    public typealias WidgetFactory = @MainActor (HomeWidgetConfiguration) -> any HomeWidget

    private let storage: PersistentStorable
    private let preferences: KeyStorable
    private let widgetFactory: WidgetFactory
    private let sync: HomeSyncObserving

    /// Default widget configurations for a fresh install (none — US-008 baseline).
    private let defaultConfigurations: [HomeWidgetConfiguration]

    /// Accounts already warned about upcoming expiration this session (avoids
    /// repeat alerts).
    private var warnedAccountIds: Set<String> = []

    public init(
        storage: PersistentStorable,
        preferences: KeyStorable,
        sync: HomeSyncObserving,
        defaultConfigurations: [HomeWidgetConfiguration] = [],
        widgetFactory: @escaping WidgetFactory
    ) {
        self.storage = storage
        self.preferences = preferences
        self.sync = sync
        self.defaultConfigurations = defaultConfigurations
        self.widgetFactory = widgetFactory
        self.state = HomeUiState(syncState: sync.syncState)

        loadWidgetConfigurations()

        // Mirror sync transitions into the UI state, and reload the dashboard
        // whenever a sync completes (lastSyncedAt advances) so freshly synced
        // data flows into the widgets (US-004).
        sync.observeSyncState { [weak self] newState in
            guard let self else { return }
            let previousTimestamp = self.state.syncState.lastSyncedAt
            self.state.syncState = newState
            if newState.lastSyncedAt != previousTimestamp {
                Task { await self.loadDashboard() }
            }
        }
    }

    // MARK: - Sync orchestration

    /// Fire-and-forget manual sync. Coalesced by the pipeline — repeated calls
    /// while a sync is in flight don't pile up (US-004 AC-2 / TC-018 / TC-078).
    public func triggerSync() {
        sync.triggerSync()
    }

    /// Pull-to-refresh: run a full sync to completion, then reload the dashboard.
    public func refresh() async {
        await sync.triggerSync().value
        await loadDashboard()
    }

    /// Reloads widget data and re-evaluates account expiration. Drives the
    /// loading indicator (US-012): the flag flips on for the duration and off
    /// when finished.
    public func loadDashboard() async {
        state.isLoading = true
        defer { state.isLoading = false }

        await reloadWidgets()
        await checkExpiredAccounts()
    }

    // MARK: - Account expiration (US-005 AC-7)

    /// Expired takes precedence over Expiring: if any account is already expired
    /// the expired alert wins, even when another (or the same) account is also
    /// expiring soon. Only when nothing is expired do we surface the
    /// expiring-soon warning (once per account per session).
    private func checkExpiredAccounts() async {
        let accounts: [AccountModel] = (try? await storage.fetchAll(AccountModel.self)) ?? []
        if let expired = accounts.first(where: { $0.isExpired }) {
            state.expiredAccount = expired
            state.showExpiredAlert = true
        } else if let expiringSoon = accounts.first(where: { $0.isExpiringSoon && !warnedAccountIds.contains($0.id) }) {
            warnedAccountIds.insert(expiringSoon.id)
            state.expiringSoonAccount = expiringSoon
            state.showExpiringSoonAlert = true
        }
    }

    // MARK: - Widgets (US-008)

    /// Moves a kind into Active. No-op if the kind is already active
    /// (duplicate-add guard — US-008 AC-4 / TC-045). Persists and loads it.
    public func addWidget(_ kind: HomeWidgetKind) {
        guard !state.widgets.contains(where: { $0.kind == kind }) else { return }
        let config = HomeWidgetConfiguration(kind: kind)
        let widget = widgetFactory(config)
        state.widgets.append(widget)
        saveWidgetConfigurations()
        Task { await widget.load() }
    }

    /// Returns a widget to Add by removing it from Active (US-008 AC-5). Persists.
    public func removeWidget(id: UUID) {
        state.widgets.removeAll { $0.id == id }
        saveWidgetConfigurations()
    }

    /// Reorders Active widgets (US-008 AC-6). Persists. Out-of-bounds /
    /// same-index moves are absorbed by `Array.move(fromOffsets:toOffset:)`
    /// (TC-080 / TC-081).
    public func moveWidgets(from source: IndexSet, to destination: Int) {
        state.widgets.moveElements(fromOffsets: source, toOffset: destination)
        saveWidgetConfigurations()
    }

    /// Kinds not currently active — the Add Widgets list.
    public func availableWidgetKinds() -> [HomeWidgetKind] {
        let active = Set(state.widgets.map { $0.kind })
        return HomeWidgetKind.allCases.filter { !active.contains($0) }
    }

    // MARK: - Persistence (US-010 AC-6)

    private func loadWidgetConfigurations() {
        let configurations: [HomeWidgetConfiguration] = preferences.object(forKey: Self.widgetsStorageKey)
            ?? defaultConfigurations
        state.widgets = configurations.map { widgetFactory($0) }
    }

    private func saveWidgetConfigurations() {
        let configurations = state.widgets.map { $0.configuration }
        preferences.setObject(configurations, forKey: Self.widgetsStorageKey)
    }

    private func reloadWidgets() async {
        for widget in state.widgets {
            await widget.load()
        }
    }
}
