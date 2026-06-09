import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

#if canImport(os)
import os
#endif

// Phase 4 · Block F · T-F16 / T-W03 / T-W06 / T-W07 / T-W08 — the window's root view + route switch.
//
// Owns the observed state (the core adapter and the navigation coordinator) and
// renders the current screen: Home when the route stack is empty, otherwise the
// pushed destination. Account management routes (accounts list, add options,
// create Apple/Firebase, import .scexport) are wired to real views.
//
// T-W03: the Apps & Reviews routes (appsList, archivedApps, appDetail,
// comingSoon, ratingsAndReviews, reviewDetail, replyComposer,
// deleteReplyConfirm) are now parameterized per §2.2. Until the real feature
// views land (T-W12, T-W19, T-W23 etc.), every new route renders a
// `WindowsPlaceholderView` with the route name/title. The switch remains
// exhaustive (no `default`) so new routes are compile-safe.
//
// T-W06: `.appsList` and `.archiveAppConfirm` are wired to real views.
// The apps list model is shared between the list and the archive confirmation
// screen so both views mutate the same state (the confirmation screen reads the
// app name from the shared model). The model is lazily created when the
// `.appsList` route is first pushed and reused by `.archiveAppConfirm` via the
// `AppsListModelCache` reference-type holder.
//
// T-W07: `.archivedApps` and `.restoreAppConfirm` are wired to real views.
// The archived apps model is shared between the archived list and the restore
// confirmation screen via the `ArchivedAppsModelCache` reference-type holder,
// mirroring the `AppsListModelCache` pattern from T-W06.
//
// T-W08: the Users tab on the Apps List screen is wired to a real
// `WindowsUsersListModel` + `WindowsUsersTabView`. The users model is lazily
// created and cached in `UsersListModelCache`, mirroring the apps/archived
// model caches. Currently no live connection is passed (same as apps); the
// connection plumbing lands with the live-sync integration.

/// Reference-type holder for the shared `WindowsAppsListModel`. Using a class
/// avoids mutating `@State` during the view body: the `@State` reference stays
/// stable, and the class's `var model` is mutated freely (T-W06).
@MainActor
private final class AppsListModelCache {
    var model: WindowsAppsListModel?

    /// Returns the cached model if it matches the requested account id; otherwise
    /// creates a new one, caches it, and returns it.
    func resolve(accountId: String, storage: PersistentStorable) -> WindowsAppsListModel {
        if let existing = model, existing.accountId == accountId {
            return existing
        }
        let newModel = WindowsAppsListModel(
            accountId: accountId,
            storage: storage
        )
        model = newModel
        return newModel
    }
}

/// Reference-type holder for the shared `WindowsArchivedAppsModel`. Mirrors
/// `AppsListModelCache` — the `@State` reference stays stable, and the class's
/// `var model` is mutated freely (T-W07).
@MainActor
private final class ArchivedAppsModelCache {
    var model: WindowsArchivedAppsModel?

    /// Returns the cached model if it matches the requested account id; otherwise
    /// creates a new one, caches it, and returns it.
    func resolve(accountId: String, storage: PersistentStorable) -> WindowsArchivedAppsModel {
        if let existing = model, existing.accountId == accountId {
            return existing
        }
        let newModel = WindowsArchivedAppsModel(
            accountId: accountId,
            storage: storage
        )
        model = newModel
        return newModel
    }
}

/// Reference-type holder for the shared `WindowsUsersListModel`. Mirrors
/// `AppsListModelCache` — the `@State` reference stays stable, and the class's
/// `var model` is mutated freely (T-W08). The users model is lazily created
/// when the `.appsList` route is first pushed and reused across tab switches.
@MainActor
private final class UsersListModelCache {
    var model: WindowsUsersListModel?

    /// Returns the cached model if it matches the requested account id; otherwise
    /// creates a new one, caches it, and returns it.
    func resolve(accountId: String) -> WindowsUsersListModel {
        if let existing = model, existing.accountId == accountId {
            return existing
        }
        let newModel = WindowsUsersListModel(
            accountId: accountId
        )
        model = newModel
        return newModel
    }
}

struct RootView: View {
    /// Observed core adapter (state + intents).
    @State private var model: WindowsHomeModel
    /// Observed navigation coordinator (route stack).
    @State private var coordinator: WindowsHomeCoordinator

    /// Shared apps list model cache. The reference-type holder keeps the model
    /// alive across route transitions (appsList -> archiveAppConfirm -> appsList)
    /// so both screens share the same state (T-W06).
    @State private var appsListCache = AppsListModelCache()

    /// Shared archived apps model cache. Mirrors `appsListCache` — the model is
    /// lazily created when the `.archivedApps` route is first pushed and reused
    /// by `.restoreAppConfirm` via the same reference-type holder (T-W07).
    @State private var archivedAppsCache = ArchivedAppsModelCache()

    /// Shared users list model cache. The model is lazily created when the
    /// `.appsList` route is first pushed and shared with the Users tab inside
    /// `WindowsAppsListView` so tab switches preserve state (T-W08).
    @State private var usersListCache = UsersListModelCache()

    init(model: WindowsHomeModel) {
        _model = State(wrappedValue: model)
        _coordinator = State(wrappedValue: model.coordinator)
    }

    var body: some View {
        currentScreen
            .task {
                // Offline-first: load the dashboard from SQLite on first appear.
                await model.loadDashboard()
            }
    }

    @ViewBuilder
    private var currentScreen: some View {
        if let route = coordinator.current {
            destination(for: route)
        } else {
            WindowsHomeView(model: model, coordinator: coordinator)
        }
    }

    /// Resolves a pushed route to its destination. Account management screens
    /// (T-F07, T-F08, T-F10, T-F11, T-F13) are real views; `reimport` is
    /// intentionally disabled (no live Apple sync on Windows v1); Apps & Reviews
    /// routes (T-W03) are placeholder-wired until their real views land.
    ///
    /// The switch is exhaustive (no `default`) so adding a route to
    /// `WindowsRoute` is a compile error until a destination is wired here.
    @ViewBuilder
    private func destination(for route: WindowsRoute) -> some View {
        switch route {

        // MARK: Account management (unchanged)

        case .customizeWidgets:
            WindowsCustomizeWidgetsView(model: model, coordinator: coordinator)

        // D7: re-import is intentionally unavailable on Windows v1.
        case .reimport:
            WindowsPlaceholderView(
                title: "Re-import",
                isDisabled: true,
                onBack: { coordinator.pop() }
            )

        // T-F07: real accounts list screen (US-W01 / US-W06).
        case .accountsList(let provider):
            WindowsAccountsListView(
                provider: provider,
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets
            )
        case .addAccountOptions(let provider):
            WindowsAddAccountOptionsView(provider: provider, coordinator: coordinator)
        // T-F10: real create Apple account form (US-W03).
        case .createAppleAccount:
            WindowsCreateAppleAccountView(
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets
            )
        case .createFirebaseAccount:
            WindowsCreateFirebaseAccountView(
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets
            )
        // T-F13: real import .scexport screen (US-W05).
        case .importScexport:
            WindowsImportAccountView(
                coordinator: coordinator,
                storage: model.storage,
                secrets: model.secrets
            )
        case .settings:
            WindowsPlaceholderView(title: "Settings") { coordinator.pop() }

        // MARK: Apps & Reviews (T-W06 real views + remaining placeholders)

        // T-W06 / T-W08: real apps list screen. The apps model is lazily created
        // and cached in `appsListCache` so the archive confirmation view (pushed
        // on top) shares the same instance. The users model is lazily created and
        // cached in `usersListCache` so tab switches preserve state (AC-W05-3).
        case .appsList(let accountId, let accountName):
            WindowsAppsListView(
                accountId: accountId,
                accountName: accountName,
                coordinator: coordinator,
                model: appsListCache.resolve(
                    accountId: accountId,
                    storage: model.storage
                ),
                usersModel: usersListCache.resolve(
                    accountId: accountId
                )
            )

        // T-W07: real archived apps screen. The model is lazily created and
        // cached in `archivedAppsCache` so the restore confirmation view
        // (pushed on top) shares the same instance.
        case .archivedApps(let accountId):
            WindowsArchivedAppsView(
                accountId: accountId,
                coordinator: coordinator,
                model: archivedAppsCache.resolve(
                    accountId: accountId,
                    storage: model.storage
                )
            )

        case .appDetail:
            WindowsPlaceholderView(title: "App Detail") { coordinator.pop() }

        case .comingSoon(let title):
            WindowsPlaceholderView(title: title) { coordinator.pop() }

        case .ratingsAndReviews:
            WindowsPlaceholderView(title: "Ratings & Reviews") { coordinator.pop() }

        case .reviewDetail:
            WindowsPlaceholderView(title: "Review Detail") { coordinator.pop() }

        case .replyComposer:
            WindowsPlaceholderView(title: "Reply Composer") { coordinator.pop() }

        case .deleteReplyConfirm:
            WindowsPlaceholderView(title: "Delete Reply") { coordinator.pop() }

        // T-W06: archive confirmation screen. Uses the shared `appsListCache`
        // so confirm/cancel mutate the same state as the apps list (TC-072:
        // pushed route, not an alert/sheet).
        case .archiveAppConfirm(let appId, let appName):
            if let listModel = appsListCache.model {
                WindowsArchiveAppConfirmView(
                    appId: appId,
                    appName: appName,
                    model: listModel,
                    coordinator: coordinator
                )
            } else {
                // Safety fallback: should never happen because archiveAppConfirm
                // is only pushed from the apps list (which creates the model).
                let _ = Self.logArchiveAppConfirmFallback()
                WindowsPlaceholderView(title: "Archive App") { coordinator.pop() }
            }

        // T-W07: restore confirmation screen. Uses the shared
        // `archivedAppsCache` so confirm/cancel mutate the same state as
        // the archived apps list (TC-072: pushed route, not an alert/sheet).
        case .restoreAppConfirm(let appId, let appName):
            if let archivedModel = archivedAppsCache.model {
                WindowsRestoreAppConfirmView(
                    appId: appId,
                    appName: appName,
                    model: archivedModel,
                    coordinator: coordinator
                )
            } else {
                // Safety fallback: should never happen because restoreAppConfirm
                // is only pushed from the archived apps list (which creates the
                // model).
                let _ = Self.logRestoreAppConfirmFallback()
                WindowsPlaceholderView(title: "Restore App") { coordinator.pop() }
            }
        }
    }

    // MARK: - Logging helpers

    /// Logs a warning when the archive-app-confirm route is rendered without a
    /// cached `WindowsAppsListModel`. Called via `let _ =` inside `@ViewBuilder`
    /// so the log fires as a side-effect before the fallback placeholder renders.
    private static func logArchiveAppConfirmFallback() {
        #if canImport(os)
        Logger(
            subsystem: "com.stackconnect.windows",
            category: "RootView"
        ).warning("[RootView] .archiveAppConfirm pushed without an AppsListModelCache model; rendering safe fallback")
        #endif
    }

    /// Logs a warning when the restore-app-confirm route is rendered without a
    /// cached `WindowsArchivedAppsModel`. Called via `let _ =` inside
    /// `@ViewBuilder` so the log fires as a side-effect before the fallback
    /// placeholder renders.
    private static func logRestoreAppConfirmFallback() {
        #if canImport(os)
        Logger(
            subsystem: "com.stackconnect.windows",
            category: "RootView"
        ).warning("[RootView] .restoreAppConfirm pushed without an ArchivedAppsModelCache model; rendering safe fallback")
        #endif
    }
}
