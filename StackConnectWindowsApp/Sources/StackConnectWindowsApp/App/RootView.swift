import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

#if canImport(os)
import os
#endif

// Phase 4 · Block F · T-F16 / T-W03 / T-W06 / T-W07 / T-W08 / T-W12 / T-W14 / T-W19 / T-W23 / T-W24 / T-W25 — the window's root view + route switch.
//
// Owns the observed state (the core adapter and the navigation coordinator) and
// renders the current screen: Home when the route stack is empty, otherwise the
// pushed destination. Account management routes (accounts list, add options,
// create Apple/Firebase, import .scexport) are wired to real views.
//
// T-W03: the Apps & Reviews routes (appsList, archivedApps, appDetail,
// comingSoon, ratingsAndReviews, reviewDetail, replyComposer,
// deleteReplyConfirm) are now parameterized per §2.2. Until the real feature
// views land (T-W24/T-W25 etc.), remaining routes render a
// `WindowsPlaceholderView` with the route name/title. The switch remains
// exhaustive (no `default`) so new routes are compile-safe.
//
// T-W19: `.ratingsAndReviews` is now wired to the real
// `WindowsRatingsReviewsView`, with a `RatingsReviewsModelCache` that
// lazily creates and caches the model per app+account pair.
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
// model caches. No `connection` is passed for now; the live-connection
// injection lands with the account-level sync integration.
//
// T-W12: `.appDetail` and `.archiveAppDetailConfirm` are wired to real views.
// The app detail model is shared between the detail and the archive-from-detail
// confirmation screen via the `AppDetailModelCache` reference-type holder,
// mirroring the `AppsListModelCache` pattern from T-W06.
//
// T-W14: verified `.appDetail`, `.comingSoon`, and `.archiveAppDetailConfirm`
// wiring satisfies AC-W07-1/2, AC-W08-1/2, and AC-W09-3. Updated ownership
// comments; no behavioral changes needed.
//
// T-W24: `.replyComposer` is now wired to the real
// `WindowsReplyComposerView`, with a `ReplyComposerModelCache` that lazily
// creates and caches the model per review+account pair.
//
// T-W25: `.deleteReplyConfirm` is now wired to the real
// `WindowsDeleteReplyConfirmView`, with a `DeleteReplyConfirmModelCache` that
// lazily creates and caches the model per review+response+account tuple.

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

/// Reference-type holder for the shared `WindowsAppDetailModel`. Mirrors
/// `AppsListModelCache` — the `@State` reference stays stable, and the class's
/// `var model` is mutated freely (T-W12). The app detail model is lazily
/// created when the `.appDetail` route is first pushed and reused by
/// `.archiveAppDetailConfirm` via the same reference-type holder.
@MainActor
private final class AppDetailModelCache {
    private var cachedAppId: String?
    private var cachedAccountId: String?
    var model: WindowsAppDetailModel?

    /// Returns the cached model if it matches the requested app+account ids;
    /// otherwise creates a new one, caches it, and returns it.
    func resolve(appId: String, accountId: String, storage: PersistentStorable) -> WindowsAppDetailModel {
        if let existing = model, cachedAppId == appId, cachedAccountId == accountId {
            return existing
        }
        let newModel = WindowsAppDetailModel(storage: storage)
        model = newModel
        cachedAppId = appId
        cachedAccountId = accountId
        return newModel
    }

    /// Invalidates the cached model (called after a confirmed archive so the
    /// freed model is not retained). The next `resolve` call creates a fresh one.
    func invalidate() {
        model = nil
        cachedAppId = nil
        cachedAccountId = nil
    }
}

/// Reference-type holder for the shared `WindowsRatingsReviewsModel`. Mirrors
/// `AppDetailModelCache` — the `@State` reference stays stable, and the class's
/// `var model` is mutated freely (T-W19). The model is lazily created when the
/// `.ratingsAndReviews` route is first pushed and reused if the same app is
/// navigated to again before the cache is invalidated.
@MainActor
private final class RatingsReviewsModelCache {
    private var cachedAppId: String?
    private var cachedAccountId: String?
    var model: WindowsRatingsReviewsModel?

    /// Returns the cached model if it matches the requested app+account ids;
    /// otherwise creates a new one, caches it, and returns it.
    func resolve(appId: String, accountId: String, storage: PersistentStorable) -> WindowsRatingsReviewsModel {
        if let existing = model, cachedAppId == appId, cachedAccountId == accountId {
            return existing
        }
        let lookupService = ITunesLookupService(storage: storage)
        let newModel = WindowsRatingsReviewsModel(
            storage: storage,
            connection: nil,
            lookupService: lookupService
        )
        model = newModel
        cachedAppId = appId
        cachedAccountId = accountId
        return newModel
    }
}

/// Reference-type holder for the shared `WindowsReviewDetailModel`. Mirrors
/// `AppDetailModelCache` — the `@State` reference stays stable, and the class's
/// `var model` is mutated freely (T-W23). The model is lazily created when the
/// `.reviewDetail` route is first pushed and reused if the same review is
/// navigated to again before the cache is invalidated.
@MainActor
private final class ReviewDetailModelCache {
    private var cachedReviewId: String?
    private var cachedAccountId: String?
    var model: WindowsReviewDetailModel?

    /// Returns the cached model if it matches the requested review+account ids;
    /// otherwise creates a new one, caches it, and returns it.
    func resolve(reviewId: String, accountId: String, storage: PersistentStorable) -> WindowsReviewDetailModel {
        if let existing = model, cachedReviewId == reviewId, cachedAccountId == accountId {
            return existing
        }
        let newModel = WindowsReviewDetailModel(storage: storage)
        model = newModel
        cachedReviewId = reviewId
        cachedAccountId = accountId
        return newModel
    }
}

/// Reference-type holder for the `WindowsReplyComposerModel`. Mirrors
/// `ReviewDetailModelCache` — the `@State` reference stays stable, and the
/// class's `var model` is mutated freely (T-W24). The model is lazily created
/// when the `.replyComposer` route is first pushed. A new model is created
/// each time the route parameters change (different reviewId, existingBody,
/// or existingResponseId), so each composer session starts fresh. Including
/// `existingResponseId` in the cache identity ensures a create-vs-edit (or
/// different responseId) re-resolves a fresh model rather than reusing a stale
/// one (AC-W13-3).
@MainActor
private final class ReplyComposerModelCache {
    private var cachedReviewId: String?
    private var cachedAccountId: String?
    private var cachedExistingBody: String?
    private var cachedExistingResponseId: String?
    var model: WindowsReplyComposerModel?

    /// Returns the cached model if it matches the requested parameters;
    /// otherwise creates a new one, caches it, and returns it.
    func resolve(
        reviewId: String,
        accountId: String,
        existingReplyBody: String?,
        existingResponseId: String?,
        storage: PersistentStorable
    ) -> WindowsReplyComposerModel {
        if let existing = model,
           cachedReviewId == reviewId,
           cachedAccountId == accountId,
           cachedExistingBody == existingReplyBody,
           cachedExistingResponseId == existingResponseId {
            return existing
        }
        let newModel = WindowsReplyComposerModel(
            reviewId: reviewId,
            accountId: accountId,
            existingReplyBody: existingReplyBody,
            existingResponseId: existingResponseId,
            storage: storage
        )
        model = newModel
        cachedReviewId = reviewId
        cachedAccountId = accountId
        cachedExistingBody = existingReplyBody
        cachedExistingResponseId = existingResponseId
        return newModel
    }
}

/// Reference-type holder for the `WindowsDeleteReplyConfirmModel`. Mirrors
/// `ReplyComposerModelCache` — the `@State` reference stays stable, and the
/// class's `var model` is mutated freely (T-W25). The model is lazily created
/// when the `.deleteReplyConfirm` route is first pushed. A new model is created
/// each time the route parameters change (different reviewId, responseId, or
/// accountId), so each confirmation session starts fresh.
@MainActor
private final class DeleteReplyConfirmModelCache {
    private var cachedReviewId: String?
    private var cachedResponseId: String?
    private var cachedAccountId: String?
    var model: WindowsDeleteReplyConfirmModel?

    /// Returns the cached model if it matches the requested parameters;
    /// otherwise creates a new one, caches it, and returns it.
    func resolve(
        reviewId: String,
        responseId: String,
        accountId: String,
        storage: PersistentStorable
    ) -> WindowsDeleteReplyConfirmModel {
        if let existing = model,
           cachedReviewId == reviewId,
           cachedResponseId == responseId,
           cachedAccountId == accountId {
            return existing
        }
        let newModel = WindowsDeleteReplyConfirmModel(
            reviewId: reviewId,
            responseId: responseId,
            accountId: accountId,
            storage: storage
        )
        model = newModel
        cachedReviewId = reviewId
        cachedResponseId = responseId
        cachedAccountId = accountId
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

    /// Shared app detail model cache. The model is lazily created when the
    /// `.appDetail` route is first pushed and reused by
    /// `.archiveAppDetailConfirm` so both views share the same state (T-W12).
    @State private var appDetailCache = AppDetailModelCache()

    /// Shared ratings & reviews model cache. The model is lazily created when
    /// the `.ratingsAndReviews` route is first pushed (T-W19).
    @State private var ratingsReviewsCache = RatingsReviewsModelCache()

    /// Shared review detail model cache. The model is lazily created when the
    /// `.reviewDetail` route is first pushed and reused if the same review is
    /// navigated to again (T-W23).
    @State private var reviewDetailCache = ReviewDetailModelCache()

    /// Reply composer model cache. The model is lazily created when the
    /// `.replyComposer` route is first pushed (T-W24). A new model is created
    /// each time the route parameters change.
    @State private var replyComposerCache = ReplyComposerModelCache()

    /// Delete reply confirm model cache. The model is lazily created when the
    /// `.deleteReplyConfirm` route is first pushed (T-W25). A new model is
    /// created each time the route parameters change.
    @State private var deleteReplyConfirmCache = DeleteReplyConfirmModelCache()

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

        // T-W12 / T-W14: real app detail screen. The detail model is lazily
        // created and cached in `appDetailCache` so the archive-from-detail
        // confirmation view (pushed on top) shares the same instance.
        //
        // T-W14 verified: wiring satisfies AC-W07-1/2 (Ratings and Reviews
        // pushes .ratingsAndReviews with correct appId/bundleId/accountId),
        // AC-W08-1/2 (7 non-functional options push .comingSoon with correct
        // titles), and AC-W09-3 (archive confirms via .archiveAppDetailConfirm,
        // pops back to apps list). No changes needed.
        case .appDetail(let appId, let accountId):
            WindowsAppDetailView(
                appId: appId,
                accountId: accountId,
                coordinator: coordinator,
                model: appDetailCache.resolve(
                    appId: appId,
                    accountId: accountId,
                    storage: model.storage
                )
            )

        // T-W12 / T-W14: coming soon placeholder, wrapped with a back
        // button so the user can navigate back from sub-routes pushed by
        // App Detail.
        //
        // T-W14 verified: wiring satisfies AC-W08-1/2 — all 7 non-functional
        // rows (App Information, App Review, History, App Privacy, App
        // Accessibility, Analytics, TestFlight) plus the platform "See All"
        // push .comingSoon with the correct title and render
        // WindowsComingSoonView with a working back button. No behavioral
        // changes needed.
        case .comingSoon(let title):
            ScrollView {
                VStack(spacing: 16) {
                    WindowsBackButtonView(onBack: { coordinator.pop() })
                    WindowsComingSoonView(title: title)
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: 860)
            }

        // T-W19: real Ratings & Reviews screen. The model is lazily created
        // and cached in `ratingsReviewsCache` so navigating back and re-entering
        // reuses the same model (preserving loaded state). No connection on
        // Windows v1 (reviews come from cache only); the aggregate rating is
        // fetched live via ITunesLookupService.
        case .ratingsAndReviews(let appId, let bundleId, let accountId):
            WindowsRatingsReviewsView(
                appId: appId,
                bundleId: bundleId,
                accountId: accountId,
                coordinator: coordinator,
                model: ratingsReviewsCache.resolve(
                    appId: appId,
                    accountId: accountId,
                    storage: model.storage
                )
            )

        // T-W23: real Review Detail screen. The model is lazily created and
        // cached in `reviewDetailCache` so navigating back and re-entering
        // reuses the same model (preserving loaded state). No connection on
        // Windows v1 (review data comes from cache only).
        case .reviewDetail(let reviewId, let appId, let accountId):
            WindowsReviewDetailView(
                reviewId: reviewId,
                appId: appId,
                accountId: accountId,
                coordinator: coordinator,
                model: reviewDetailCache.resolve(
                    reviewId: reviewId,
                    accountId: accountId,
                    storage: model.storage
                )
            )

        // T-W24: real Reply Composer screen. The model is lazily created and
        // cached in `replyComposerCache`. Supports both create (nil
        // existingReplyBody) and edit (pre-populated) flows. No connection on
        // Windows v1 (reply submission requires a live connection, which will
        // be wired when account-level sync lands). The `existingResponseId` is
        // threaded from the route so the model can upsert the correct response
        // without relying solely on cache resolution (AC-W13-3).
        case .replyComposer(let reviewId, let accountId, let existingReplyBody, let existingResponseId):
            WindowsReplyComposerView(
                reviewId: reviewId,
                accountId: accountId,
                existingReplyBody: existingReplyBody,
                coordinator: coordinator,
                model: replyComposerCache.resolve(
                    reviewId: reviewId,
                    accountId: accountId,
                    existingReplyBody: existingReplyBody,
                    existingResponseId: existingResponseId,
                    storage: model.storage
                )
            )

        // T-W25: real Delete Reply Confirm screen. The model is lazily created
        // and cached in `deleteReplyConfirmCache`. A new model is created each
        // time the route parameters change (different reviewId, responseId, or
        // accountId). No connection on Windows v1 (delete requires a live
        // connection, which will be wired when account-level sync lands).
        case .deleteReplyConfirm(let reviewId, let responseId, let accountId):
            WindowsDeleteReplyConfirmView(
                reviewId: reviewId,
                responseId: responseId,
                accountId: accountId,
                coordinator: coordinator,
                model: deleteReplyConfirmCache.resolve(
                    reviewId: reviewId,
                    responseId: responseId,
                    accountId: accountId,
                    storage: model.storage
                )
            )

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

        // T-W12 / T-W14: archive-from-detail confirmation screen. Uses the
        // shared `appDetailCache` so confirm mutates the same detail model
        // that owns the app state (TC-072: pushed route, not an alert/sheet).
        // On confirmed archive, the cache is invalidated so the freed model
        // is not retained across future navigations (SF-2).
        //
        // T-W14 verified: AC-W09-3 (double-pop back to apps list after
        // confirmed archive).
        case .archiveAppDetailConfirm(let appId, let appName, let accountId):
            if let detailModel = appDetailCache.model {
                WindowsArchiveAppDetailConfirmView(
                    appId: appId,
                    appName: appName,
                    accountId: accountId,
                    model: detailModel,
                    coordinator: coordinator,
                    onArchiveConfirmed: { [appDetailCache] in
                        appDetailCache.invalidate()
                    }
                )
            } else {
                // Safety fallback: should never happen because
                // archiveAppDetailConfirm is only pushed from the app detail
                // (which creates the model).
                let _ = Self.logArchiveAppDetailConfirmFallback()
                WindowsPlaceholderView(title: "Archive App") { coordinator.pop() }
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

    /// Logs a warning when the archive-app-detail-confirm route is rendered
    /// without a cached `WindowsAppDetailModel`. Called via `let _ =` inside
    /// `@ViewBuilder` so the log fires as a side-effect before the fallback
    /// placeholder renders.
    private static func logArchiveAppDetailConfirmFallback() {
        #if canImport(os)
        Logger(
            subsystem: "com.stackconnect.windows",
            category: "RootView"
        ).warning("[RootView] .archiveAppDetailConfirm pushed without an AppDetailModelCache model; rendering safe fallback")
        #endif
    }
}
