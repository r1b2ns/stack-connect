import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

// Phase 4 · B1b-2 · T-B2 — the SwiftCrossUI seam over the shared core.
//
// The Foundation-pure `StackHomeCore.HomeViewModel` (T-A10) is not a
// SwiftCrossUI `ObservableObject`. This thin adapter owns it, republishes its
// `HomeUiState` via `@Published state` so the SwiftCrossUI views redraw, and
// forwards the Home intents. It mirrors the role the iOS `HomeViewModel` adapter
// plays for SwiftUI — same core, different UI framework.

/// SwiftCrossUI-facing adapter around the shared core `HomeViewModel`.
@MainActor
final class WindowsHomeModel: SwiftCrossUI.ObservableObject {

    /// Republished snapshot of the core view model's state. Kept current via the
    /// core's `onStateChanged` callback; `@Published` drives SwiftCrossUI redraws.
    //
    // `Published`/`ObservableObject` are qualified because on the macOS host
    // Foundation re-exports Combine's same-named symbols; on Windows there is no
    // Combine so the qualification is harmless.
    @SwiftCrossUI.Published var state: HomeUiState

    /// The Windows navigation coordinator (route stack). Held here so a single
    /// bootstrap owns both the core model and navigation.
    let coordinator: WindowsHomeCoordinator

    private let core: StackHomeCore.HomeViewModel

    init(environment: AppEnvironment) {
        let storage = environment.storage
        let coordinator = WindowsHomeCoordinator()
        let core = StackHomeCore.HomeViewModel(
            storage: storage,
            preferences: environment.preferences,
            sync: WindowsNoOpSyncObserver(),
            widgetFactory: { configuration in
                WindowsHomeModel.makeWidget(configuration, storage: storage)
            }
        )
        self.core = core
        self.coordinator = coordinator
        self.state = core.state
        core.onStateChanged = { [weak self] newState in
            self?.state = newState
        }
    }

    // MARK: - Intents

    /// Loads the dashboard from the local SQLite store (offline-first). Wired to
    /// run on first appear and after a sync.
    func loadDashboard() async {
        await core.loadDashboard()
    }

    /// Manual sync. No live Apple sync on Windows v1 (D7) — the injected
    /// observer is a no-op, so this is currently inert but kept wired for parity.
    func triggerSync() {
        core.triggerSync()
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

    // MARK: - Widget factory

    /// Builds the Foundation-pure core widget data object for a configuration.
    /// The Windows widget *views* (T-C*) render from these same data objects.
    private static func makeWidget(
        _ configuration: HomeWidgetConfiguration,
        storage: PersistentStorable
    ) -> any HomeWidget {
        switch configuration.kind {
        case .inReview:
            return InReviewWidget(configuration: configuration, storage: storage)
        case .awaitingRelease:
            return AwaitingReleaseWidget(configuration: configuration, storage: storage)
        case .recentReviews:
            return RecentReviewsWidget(configuration: configuration, storage: storage)
        }
    }
}

/// A `HomeSyncObserving` that does nothing — Windows v1 has no live Apple sync
/// (D7). It satisfies the core `HomeViewModel`'s sync dependency so the rest of
/// the Home (offline-first load from SQLite, widgets, navigation) works without
/// the App Store Connect SDK. A real Windows sync conformer lands later.
@MainActor
final class WindowsNoOpSyncObserver: HomeSyncObserving {
    var syncState: SyncState { SyncState() }

    @discardableResult
    func triggerSync() -> Task<Void, Never> {
        Task {}
    }

    func observeSyncState(_ onChange: @escaping (SyncState) -> Void) {
        // No transitions to report in v1.
    }
}
