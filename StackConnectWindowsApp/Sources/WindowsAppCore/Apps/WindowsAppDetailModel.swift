import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols

#if canImport(os)
import os
#endif

// T-W11 — App Detail model for the Windows GUI.
//
// SwiftCrossUI `ObservableObject` adapter that provides offline-first loading,
// optional live refresh, favorite toggling, and archiving for the App Detail
// screen (Feature 2).
//
// Mirrors `WindowsAppsListModel` / `WindowsArchivedAppsModel` conventions:
// `@MainActor`, `SwiftCrossUI.ObservableObject`/`@SwiftCrossUI.Published`, DI
// via init (`storage: PersistentStorable`, optional `connection`), offline-first
// cache load, revert-on-failure for mutations.
//
// The model exposes the detail header data (icon, name, bundle ID, status +
// color, version) and the option sections for the App Detail screen. Navigation
// and routing to sub-screens is the view's responsibility (T-W12).

// MARK: - Section Data Structures

/// A single option row within an App Detail section.
public struct AppDetailOption: Hashable, Sendable {
    /// The display title for the option row.
    public let title: String

    /// Whether this option is functional (navigates to a real screen) or
    /// merely a coming-soon placeholder.
    public let isFunctional: Bool

    public init(title: String, isFunctional: Bool = false) {
        self.title = title
        self.isFunctional = isFunctional
    }
}

/// A section in the App Detail screen, grouping related option rows.
public struct AppDetailSection: Hashable, Sendable {
    /// The section header title.
    public let title: String

    /// The option rows within this section.
    public let options: [AppDetailOption]

    public init(title: String, options: [AppDetailOption]) {
        self.title = title
        self.options = options
    }
}

// MARK: - UI State

/// The complete UI state for the App Detail screen.
public struct AppDetailUiState {
    /// The loaded app (nil before first load).
    public var app: AppModel?

    /// True while the initial cache load or live refresh is in progress.
    public var isLoading: Bool = false

    /// Non-nil when a live refresh or mutation fails; the cached detail
    /// remains visible.
    public var syncError: String? = nil

    /// The option sections for the App Detail screen.
    public var sections: [AppDetailSection] = []

    public init(
        app: AppModel? = nil,
        isLoading: Bool = false,
        syncError: String? = nil,
        sections: [AppDetailSection] = []
    ) {
        self.app = app
        self.isLoading = isLoading
        self.syncError = syncError
        self.sections = sections
    }
}

// MARK: - Model

/// App Detail model for a single app. Owns the state the App Detail view
/// binds to and exposes intents for loading, favoriting, and archiving.
@MainActor
public final class WindowsAppDetailModel: SwiftCrossUI.ObservableObject {

    // MARK: - Published State

    @SwiftCrossUI.Published public private(set) var uiState = AppDetailUiState()

    // MARK: - Dependencies

    private let storage: PersistentStorable
    private let connection: AppleConnectionProtocol?

    // MARK: - Init

    /// Creates a new app detail model.
    ///
    /// - Parameters:
    ///   - storage: Persistent storage backend (SQLite on Windows).
    ///   - connection: Optional Apple connection for live refresh. When nil,
    ///     only cached data is shown (useful for offline or test scenarios).
    public init(
        storage: PersistentStorable,
        connection: AppleConnectionProtocol? = nil
    ) {
        self.storage = storage
        self.connection = connection
    }

    // MARK: - Load (Offline-First + Optional Live Refresh)

    /// Loads the app from cache first (synchronously surfaces cached state),
    /// then optionally live-refreshes from the API.
    ///
    /// On live-refresh failure, the cached app remains shown and
    /// `uiState.syncError` is set (the cached app is never cleared).
    ///
    /// - Parameters:
    ///   - appId: The App Store app identifier.
    ///   - accountId: The account this app belongs to.
    public func loadAppIfNeeded(appId: String, accountId: String) async {
        uiState.isLoading = true
        uiState.syncError = nil

        // Phase 1: Load from cache
        var cachedApp: AppModel?
        do {
            let allApps: [AppModel] = try await storage.fetchAll(AppModel.self)
            cachedApp = allApps.first { $0.id == appId && $0.accountId == accountId }
        } catch {
            // Cache load failure: no data yet, but not a fatal error.
            cachedApp = nil
        }

        if let cachedApp {
            uiState.app = cachedApp
        }

        // If no connection, we are done after cache.
        guard let connection else {
            // Assign sections once when an app was found (sections accompany a non-nil app).
            if uiState.app != nil {
                uiState.sections = Self.buildSections()
            }
            uiState.isLoading = false
            return
        }

        // Phase 2: Live refresh — attempt to fetch fresh app data from the API.
        // The API returns the full apps list; we find ours by id.
        do {
            let remoteApps = try await connection.fetchApps()
            if let remoteInfo = remoteApps.first(where: { $0.id == appId }) {
                // Merge remote data with local flags (isFavorite, isArchived, etc.)
                let merged = AppModel(
                    id: remoteInfo.id,
                    name: remoteInfo.name,
                    bundleId: remoteInfo.bundleId,
                    platform: remoteInfo.platform,
                    accountId: accountId,
                    iconUrl: cachedApp?.iconUrl,
                    appStoreState: cachedApp?.appStoreState,
                    versionString: cachedApp?.versionString,
                    lastModifiedDate: cachedApp?.lastModifiedDate,
                    isArchived: cachedApp?.isArchived ?? false,
                    isFavorite: cachedApp?.isFavorite ?? false,
                    hasReviewPending: cachedApp?.hasReviewPending ?? false,
                    platformVersions: cachedApp?.platformVersions
                )
                uiState.app = merged

                // Persist the merged model
                try await storage.save(merged, id: "\(accountId).\(merged.id)")
            }
        } catch {
            // On live-refresh failure, keep the cached app shown and set error.
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "AppDetail")
                .warning("[AppDetail] Live refresh failed for app \(appId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            uiState.syncError = "Sync failed. Showing cached data."
        }

        // Assign sections exactly once at the end when an app is available.
        if uiState.app != nil {
            uiState.sections = Self.buildSections()
        }
        uiState.isLoading = false
    }

    // MARK: - Favorite Toggle

    /// Toggles the `isFavorite` flag for the given app. The change is applied
    /// optimistically to the UI, then persisted. On persistence failure the
    /// change is reverted and `uiState.syncError` is set.
    public func toggleFavorite(appId: String) async {
        guard var app = uiState.app, app.id == appId else { return }
        uiState.syncError = nil

        // Optimistic update
        app.isFavorite.toggle()
        uiState.app = app

        do {
            try await storage.save(app, id: "\(app.accountId).\(app.id)")
        } catch {
            // Revert on failure
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "AppDetail")
                .warning("[AppDetail] Failed to persist favorite toggle for app \(appId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            app.isFavorite.toggle()
            uiState.app = app
            uiState.syncError = "Failed to update favorite."
        }
    }

    // MARK: - Archive

    /// Sets `isArchived = true` on the app, persists the change. On
    /// persistence failure the optimistic change is reverted and
    /// `uiState.syncError` is set.
    ///
    /// The confirmation screen and pop-back navigation are the view's
    /// concern (T-W12); the model just performs the archive + persistence
    /// and exposes the `isArchived` state.
    public func archiveApp(appId: String, accountId: String) async {
        guard var app = uiState.app, app.id == appId else { return }
        uiState.syncError = nil

        // Optimistic update
        app.isArchived = true
        uiState.app = app

        do {
            try await storage.save(app, id: "\(accountId).\(app.id)")
        } catch {
            // Revert on failure
            #if canImport(os)
            Logger(subsystem: "com.stackconnect.windows", category: "AppDetail")
                .warning("[AppDetail] Failed to persist archive for app \(appId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            #endif
            app.isArchived = false
            uiState.app = app
            uiState.syncError = "Failed to archive app."
        }
    }

    // MARK: - Sections Builder

    /// Builds the static option sections for the App Detail screen.
    ///
    /// Section titles and option titles use plain strings that map to the
    /// cross-platform localization approach used by the Windows port (the
    /// `localizedString` helper in StackHomeCore is internal; at the
    /// presentation boundary the View layer can wrap these for localization).
    ///
    /// Section structure per spec:
    /// - "General": App Information, App Review, History
    /// - "App Store": App Privacy, App Accessibility, Ratings and Reviews
    /// - "Analytics" (leaf section, no sub-options)
    /// - "TestFlight" (leaf section, no sub-options)
    ///
    /// Only "Ratings and Reviews" is functional; all others are coming-soon.
    static func buildSections() -> [AppDetailSection] {
        [
            AppDetailSection(
                title: "General",
                options: [
                    AppDetailOption(title: "App Information", isFunctional: false),
                    AppDetailOption(title: "App Review", isFunctional: false),
                    AppDetailOption(title: "History", isFunctional: false),
                ]
            ),
            AppDetailSection(
                title: "App Store",
                options: [
                    AppDetailOption(title: "App Privacy", isFunctional: false),
                    AppDetailOption(title: "App Accessibility", isFunctional: false),
                    AppDetailOption(title: "Ratings and Reviews", isFunctional: true),
                ]
            ),
            AppDetailSection(
                title: "Analytics",
                options: []
            ),
            AppDetailSection(
                title: "TestFlight",
                options: []
            ),
        ]
    }
}
