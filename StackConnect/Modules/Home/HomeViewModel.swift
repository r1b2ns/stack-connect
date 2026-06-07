import Foundation
import StackHomeCore
#if canImport(Combine)
import Combine
#endif

// The Home dashboard logic now lives in StackHomeCore (Foundation-pure,
// `StackHomeCore.HomeViewModel`, T-A10): state shaping, manual + auto sync
// orchestration, account-expiration precedence, widget add/remove/reorder, and
// widget-configuration load+save via `KeyStorable`. This file keeps only the
// iOS seam:
//
//  - `HomeUiState` re-exports the core UI state value type so the SwiftUI views
//    and `HomeViewModelProtocol` keep their existing name.
//  - `HomeViewModel` — a thin `ObservableObject` adapter that owns a core
//    `HomeViewModel`, republishes its `state` via `@Published uiState`, and
//    forwards intents. The SwiftUI Home view / CustomizeWidgets sheet observe
//    `$uiState` exactly as before (US-010 AC-2). Widgets are built by the iOS
//    `HomeWidgetRegistry` (observable adapters) and injected into core via its
//    `widgetFactory`, so core never references the registry.

// MARK: - UiState

/// iOS alias for the Foundation-pure core Home UI state.
typealias HomeUiState = StackHomeCore.HomeUiState

// MARK: - Protocol

@MainActor
protocol HomeViewModelProtocol: ObservableObject {
    var uiState: HomeUiState { get set }
    func loadDashboard() async
    func triggerSync()
    func refresh() async
    func addWidget(_ kind: HomeWidgetKind)
    func removeWidget(id: UUID)
    func moveWidgets(from source: IndexSet, to destination: Int)
    func availableWidgetKinds() -> [HomeWidgetKind]
}

// MARK: - iOS adapter

@MainActor
final class HomeViewModel: HomeViewModelProtocol {

    /// Republished snapshot of the core view model's `HomeUiState`. Kept in sync
    /// via the core's `onStateChanged` callback. `@Published` preserves the
    /// `$uiState` Combine publisher the SwiftUI views bind to (incl. the two-way
    /// `$uiState.showExpiredAlert` alert bindings).
    @Published var uiState: HomeUiState

    private let core: StackHomeCore.HomeViewModel

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared,
        preferences: KeyStorable = UserDefaultsStorable(),
        syncService: SyncService = .shared
    ) {
        let resolvedStorage: any PersistentStorable = storage ?? SwiftDataStorable.shared
        core = StackHomeCore.HomeViewModel(
            storage: resolvedStorage,
            preferences: preferences,
            sync: syncService,
            widgetFactory: { config in
                HomeWidgetRegistry.make(for: config, storage: resolvedStorage)
            }
        )
        // Mirror the initial snapshot, then republish every change.
        uiState = core.state
        core.onStateChanged = { [weak self] newState in
            self?.uiState = newState
        }
    }

    func triggerSync() {
        core.triggerSync()
    }

    func refresh() async {
        await core.refresh()
    }

    func loadDashboard() async {
        await core.loadDashboard()
    }

    func addWidget(_ kind: HomeWidgetKind) {
        core.addWidget(kind)
    }

    func removeWidget(id: UUID) {
        core.removeWidget(id: id)
    }

    func moveWidgets(from source: IndexSet, to destination: Int) {
        core.moveWidgets(from: source, to: destination)
    }

    func availableWidgetKinds() -> [HomeWidgetKind] {
        core.availableWidgetKinds()
    }
}
