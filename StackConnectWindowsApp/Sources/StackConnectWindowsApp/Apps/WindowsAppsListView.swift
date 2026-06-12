import Foundation
import SwiftCrossUI
import StackHomeCore
import StackProtocols
import WindowsAppCore

// T-W06 — Apps List screen for the Windows GUI.
//
// Displays the apps belonging to a single Apple account, with a toolbar (back,
// account title, Archived button, Refresh button), a search field,
// Favorites/All Apps sections, and archive-with-confirmation.
//
// The view binds to `WindowsAppsListModel` (T-W05) which owns the apps array,
// loading/error/search/archive state, and computed groupings. The view is
// purely declarative -- all mutations go through the model's intents.
//
// Layout follows the Windows app convention: content capped at 860px, padded
// 16px, with a `ScrollView` + `VStack`. The toolbar uses `WindowsBackButtonView`
// for the "< Back" action (pops to prior screen).
//
// Archive flow (AC-W04): the Archive button on each row calls
// `model.archiveApp(appId:)` (which sets the confirmation intent) and then
// pushes an archive-confirm route via the coordinator. On confirm, the
// confirmation screen calls the model's `archiveAppConfirmed` (the model is
// stored in RootView and shared between both routes). On cancel/back, calls
// `model.cancelArchive` and pops. This uses a PUSHED ROUTE (TC-072), not an
// alert/sheet.

struct WindowsAppsListView: View {

    /// The account id this list displays apps for.
    let accountId: String
    /// The display name for the toolbar title.
    let accountName: String
    /// Navigation coordinator -- Back pops, Archived pushes the archived route.
    @State private var coordinator: WindowsHomeCoordinator
    /// The apps list model. Observed via `@State` so the view redraws when the
    /// model's `@Published` properties change. The same instance is shared with
    /// the archive confirmation view via the RootView's `AppsListModelCache`.
    @State private var model: WindowsAppsListModel

    init(
        accountId: String,
        accountName: String,
        coordinator: WindowsHomeCoordinator,
        model: WindowsAppsListModel
    ) {
        self.accountId = accountId
        self.accountName = accountName
        _coordinator = State(wrappedValue: coordinator)
        _model = State(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                toolbar
                syncErrorBanner
                appsTabContent
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: 860)
        }
        .task {
            await model.loadApps()
        }
    }

    // MARK: - Toolbar (back + title + Archived + Refresh)

    /// Header: "< Back" on the left, account name as title, "Archived" and
    /// "Refresh" buttons on the right. Refresh triggers the model's live sync
    /// (TC-070: explicit button, NO pull-to-refresh). Archived navigates to
    /// the `.archivedApps(accountId:)` route.
    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack {
                WindowsBackButtonView(onBack: { coordinator.pop() })
                Spacer()
                Button("Archived") {
                    coordinator.push(.archivedApps(accountId: accountId))
                }
                Button("Refresh") {
                    Task {
                        await model.loadApps()
                    }
                }
            }
            HStack {
                Text(accountName)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
        }
    }

    // MARK: - Sync Error Banner (AC-W01: non-blocking sync-error)

    /// Inline error banner shown when a sync fails. Uses the InfoBar convention
    /// (4px colored left border + message). Cached rows remain visible below
    /// (TC-011).
    @ViewBuilder
    private var syncErrorBanner: some View {
        if let error = model.syncError {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 4)
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Text(error)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(12)
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }

    // MARK: - Apps Tab Content

    @ViewBuilder
    private var appsTabContent: some View {
        // Search field (AC-W02: filters name + bundleId via model)
        searchField

        if model.isLoading && model.apps.isEmpty {
            // AC-W01-4: First load -> loading indicator (no stale/partial content)
            loadingState
        } else if model.isSearchEmpty {
            // AC-W02-3: Search with no matches -> empty search state
            searchEmptyState
        } else if model.isEmpty {
            // AC-W01-3: No apps -> empty state
            emptyState
        } else {
            populatedState
        }
    }

    // MARK: - Search Field (AC-W02-1..5)

    /// A search `TextField` bound to the model's search query, filtering both
    /// sections live. Independent per section (AC-W02-4); empty sections hidden
    /// (AC-W02-5).
    private var searchField: some View {
        HStack(spacing: 8) {
            Text("[?]")
                .foregroundColor(.gray)
            TextField("Search apps...", text: $model.searchQuery)
        }
        .padding(8)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Loading State (AC-W01-4)

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading apps...")
                .foregroundColor(.gray)
            Spacer()
        }
    }

    // MARK: - Empty State (AC-W01-3 / TC-010)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("( * )")
                .font(.title2)
                .foregroundColor(.gray)
            Text("No Apps")
                .font(.title2)
                .fontWeight(.semibold)
            Text("This account has no apps yet. Use Refresh to sync from App Store Connect.")
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search Empty State (AC-W02-3)

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No Results")
                .font(.title2)
                .fontWeight(.semibold)
            Text("No apps match your search.")
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Populated State (AC-W01-5: Favorites above All Apps)

    /// Renders the Favorites section above the All Apps section.
    /// Empty sections are hidden (AC-W01-5 / AC-W02-5).
    @ViewBuilder
    private var populatedState: some View {
        // Favorites section (only shown when non-empty)
        if !model.favoriteApps.isEmpty {
            WindowsSectionHeader(title: "Favorites")
            ForEach(model.favoriteApps, id: \.id) { app in
                appRow(app)
            }
        }

        // All Apps section (only shown when non-empty)
        if !model.allApps.isEmpty {
            WindowsSectionHeader(title: "All Apps")
            ForEach(model.allApps, id: \.id) { app in
                appRow(app)
            }
        }
    }

    // MARK: - App Row + Archive Flow

    /// A single app row with navigation, favorite toggle, and archive wiring.
    private func appRow(_ app: AppModel) -> some View {
        WindowsAppRow(
            app: app,
            onTap: {
                // Row tap -> appDetail navigation
                coordinator.push(.appDetail(appId: app.id, accountId: accountId))
            },
            onToggleFavorite: {
                // AC-W03: Favorite toggle moves app between sections immediately,
                // persists via model (survives restart).
                Task {
                    await model.toggleFavorite(appId: app.id)
                }
            },
            onArchive: {
                // AC-W04: Archive button sets the confirmation intent on the model
                // and pushes a confirmation route (TC-072: pushed route, not alert).
                model.archiveApp(appId: app.id)
                coordinator.push(
                    .archiveAppConfirm(
                        appId: app.id,
                        appName: app.name
                    )
                )
            }
        )
    }

}
