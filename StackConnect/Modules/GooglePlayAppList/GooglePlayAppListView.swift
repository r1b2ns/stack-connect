import SwiftUI
import TipKit

// MARK: - Factory

@MainActor
struct GooglePlayAppListViewFactory {
    static func build(account: AccountModel) -> some View {
        GooglePlayAppListEntry(account: account)
    }
}

// MARK: - Entry

/// Owns both tabs of a Google Play account (plan U9, prototype 1 / 16): the
/// "Apps | Users" switch, the account title and the trailing toolbar button,
/// like the App Store `AppListEntry`. Users shows only with `canView(.users)`.
private struct GooglePlayAppListEntry: View {
    let account: AccountModel

    @StateObject private var viewModel: GooglePlayAppListViewModel
    @StateObject private var usersViewModel: GooglePlayUsersViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator
    @State private var selectedTab: AppListTab = .apps

    init(account: AccountModel) {
        self.account = account
        _viewModel = StateObject(wrappedValue: GooglePlayAppListViewModel(account: account))
        _usersViewModel = StateObject(wrappedValue: GooglePlayUsersViewModel(account: account))
    }

    private var availableTabs: [AppListTab] {
        AppListTab.allCases.filter { tab in
            switch tab {
            case .apps: return true
            case .usersAndAccess: return account.canView(.users)
            }
        }
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .apps:
                GooglePlayAppListView(viewModel: viewModel)
            case .usersAndAccess:
                GooglePlayUsersView(viewModel: usersViewModel)
            }
        }
        .navigationTitle(account.name)
        .toolbar { buildToolbar() }
    }

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if availableTabs.count > 1 {
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "Section"), selection: $selectedTab) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }

        // Apps: account-level actions (settings, rename, export, delete), as
        // on the App Store app list. Users: invite (prototype 16).
        ToolbarItem(placement: .topBarTrailing) {
            switch selectedTab {
            case .apps:
                StackTrackedButton(.accountSettings, on: .googlePlayAppList) {
                    homeCoordinator.navigateToAccountManagement(account)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(String(localized: "Manage Account"))
            case .usersAndAccess:
                if usersViewModel.uiState.canShowInvite {
                    StackTrackedButton(.inviteUser, on: .googlePlayUsers) {
                        usersViewModel.uiState.showInvite = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Invite User"))
                }
            }
        }
    }
}

// MARK: - View

struct GooglePlayAppListView<ViewModel: GooglePlayAppListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    /// Same tip as the App Store list (archive / favorite by swiping).
    private let swipeActionsTip = AppListSwipeActionsTip()

    private var isRunningOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    var body: some View {
        // iOS 26 chrome of the App Store app list (prototype screen 1): large
        // account title, search drawer, round glass toolbar buttons.
        buildContent()
            .trackScreen(.googlePlayAppList)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search by name or package")
            )
            .trackSearch(query: viewModel.uiState.searchQuery, resultCount: viewModel.uiState.filteredApps.count, on: .googlePlayAppList)
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .refreshable { await viewModel.refresh() }
            .sheet(isPresented: $viewModel.uiState.showAddApp) {
                AddGooglePlayAppSheet(
                    isAdding: viewModel.uiState.isAdding,
                    error: viewModel.uiState.addError,
                    footer: viewModel.uiState.addAppFooter,
                    onAdd: { packageName in
                        Task { await viewModel.addApp(packageName: packageName) }
                    },
                    onCancel: {
                        viewModel.uiState.showAddApp = false
                        viewModel.uiState.addError = nil
                    }
                )
            }
            .toast(
                isPresented: $viewModel.uiState.showSyncToast,
                message: String(localized: "Syncing apps...")
            )
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.apps.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.uiState.error, viewModel.uiState.apps.isEmpty {
            StackErrorContentView(
                message: error,
                reportContext: errorReportContext,
                // The Retry tap is tracked by `StackErrorContentView`.
                onRetry: { Task { await viewModel.load() } }
            ) {
                if viewModel.uiState.canAddApps {
                    StackTrackedButton(String(localized: "Add Manually"), button: .add, on: .googlePlayAppList) {
                        viewModel.uiState.showAddApp = true
                    }
                }
            }
            .stackAccountStatusInset(viewModel.uiState.accountStatus)
        } else if viewModel.uiState.visibleApps.isEmpty {
            // No apps, or every app archived (still reachable from the
            // bottom bar's "Archived").
            buildEmptyState()
                .stackAccountStatusInset(viewModel.uiState.accountStatus)
        } else if viewModel.uiState.filteredApps.isEmpty {
            ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
        } else {
            buildList()
        }
    }

    /// Where an error on this screen happened, for its shared report (the
    /// account's app list: no app yet).
    private var errorReportContext: ErrorReportContext {
        ErrorReportContext(screen: String(localized: "Apps"), account: viewModel.uiState.account)
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if viewModel.uiState.canAddApps {
            ContentUnavailableView {
                Label(String(localized: "No Apps"), systemImage: "ipod.and.applewatch")
            } description: {
                Text("No apps found for this account. You can add apps manually by package name.")
            } actions: {
                StackTrackedButton(String(localized: "Add App"), button: .add, on: .googlePlayAppList) {
                    viewModel.uiState.showAddApp = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Apps"), systemImage: "ipod.and.applewatch")
            } description: {
                Text("No apps found for this account.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            StackAccountStatusSection(status: viewModel.uiState.accountStatus)

            // Inline banner for a failed sync while the cached list stays on screen.
            if let error = viewModel.uiState.error {
                StackInlineErrorSection(message: error, reportContext: errorReportContext)
            }

            if !isRunningOnMac {
                TipView(swipeActionsTip)
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                    .padding(.zero)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            // Favorites first, like the App Store list.
            if !viewModel.uiState.favoriteApps.isEmpty {
                Section {
                    ForEach(viewModel.uiState.favoriteApps) { app in
                        buildAppButton(app)
                    }
                } header: {
                    Label(String(localized: "Favorites"), systemImage: "star.fill")
                }
            }

            Section {
                ForEach(viewModel.uiState.regularApps) { app in
                    buildAppButton(app)
                }
            } header: {
                if !viewModel.uiState.favoriteApps.isEmpty {
                    Text(String(localized: "All Apps"))
                }
            } footer: {
                buildReleaseStatusPausedFooter()
            }
        }
    }

    private func buildAppButton(_ app: GooglePlayAppItem) -> some View {
        Button {
            homeCoordinator.navigateToGooglePlayAppDetail(app, account: viewModel.uiState.account)
        } label: {
            buildAppRow(app)
        }
        .foregroundStyle(.primary)
        .contextMenu { buildAppContextMenu(app) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Task { await viewModel.toggleArchive(app: app) }
            } label: {
                Label(String(localized: "Archive"), systemImage: "archivebox.fill")
            }
            .tint(.gray)

            Button {
                Task { await viewModel.toggleFavorite(app: app) }
            } label: {
                Label(
                    app.isFavorite ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                    systemImage: app.isFavorite ? "star.slash.fill" : "star.fill"
                )
            }
            .tint(.yellow)
        }
    }

    /// Subtle note while a Google Play quota cooldown pauses the release
    /// status: the cached lines stay, nothing blocks.
    @ViewBuilder
    private func buildReleaseStatusPausedFooter() -> some View {
        if let note = viewModel.uiState.releaseStatusPausedNote {
            Label(note, systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func buildAppRow(_ app: GooglePlayAppItem) -> some View {
        HStack(spacing: 12) {
            // The green Play tile stands in until (or unless) the store icon loads.
            StackAppIcon(url: app.iconURL, size: 44, cornerRadius: 10) {
                StackIconTile(systemName: "play.fill", color: .green, size: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                buildStatusLines(app)

                if app.isManuallyAdded {
                    Text(String(localized: "Added manually"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isRunningOnMac {
                buildInlineArchiveButton(app)
            }

            buildFavoriteStar(app)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Mac: one-click archive in the row (the iPhone swipe action).
    private func buildInlineArchiveButton(_ app: GooglePlayAppItem) -> some View {
        Button {
            Task { await viewModel.toggleArchive(app: app) }
        } label: {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(.gray)
        }
        .buttonStyle(.borderless)
        .help(String(localized: "Archive"))
        .accessibilityLabel(String(localized: "Archive"))
    }

    /// Star toggle, like the App Store list's.
    private func buildFavoriteStar(_ app: GooglePlayAppItem) -> some View {
        Button {
            Task { await viewModel.toggleFavorite(app: app) }
        } label: {
            Image(systemName: app.isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(app.isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .help(app.isFavorite ? String(localized: "Unfavorite") : String(localized: "Favorite"))
        .accessibilityLabel(app.isFavorite ? String(localized: "Unfavorite") : String(localized: "Favorite"))
    }

    /// One line per track with a release ("● Production · In review (4.2.0)"),
    /// like the App Store list's one line per platform. Without a cached status
    /// (or without the `version` rule) the package name stands in, unless the
    /// title already is the package name.
    @ViewBuilder
    private func buildStatusLines(_ app: GooglePlayAppItem) -> some View {
        let lines = viewModel.uiState.releaseStatus[app.packageName] ?? []
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines) { line in
                    StackStatusLine(
                        color: line.lifecycleState.color,
                        text: line.text,
                        detail: line.versionName,
                        trailingGlyph: .android,
                        wraps: true
                    )
                }
            }
        } else if app.title != nil {
            Text(app.packageName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func buildAppContextMenu(_ app: GooglePlayAppItem) -> some View {
        Button {
            Task { await viewModel.toggleFavorite(app: app) }
        } label: {
            Label(
                app.isFavorite ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                systemImage: app.isFavorite ? "star.slash.fill" : "star.fill"
            )
        }
        Button {
            Task { await viewModel.toggleArchive(app: app) }
        } label: {
            Label(String(localized: "Archive"), systemImage: "archivebox.fill")
        }
        if app.isManuallyAdded && viewModel.uiState.canDeleteApps {
            Button(role: .destructive) {
                Task { await viewModel.removeApp(app) }
            } label: {
                Label(String(localized: "Remove"), systemImage: "trash")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        // The title, the tab switch and the gear belong to the entry.
        // "Add by package name" floats bottom-leading; Archived sits
        // bottom-trailing, like the App Store list.
        ToolbarItemGroup(placement: .bottomBar) {
            if viewModel.uiState.canAddApps {
                StackTrackedButton(.add, on: .googlePlayAppList) {
                    viewModel.uiState.showAddApp = true
                } label: {
                    Label(String(localized: "Add App"), systemImage: "plus")
                }
                .accessibilityLabel(String(localized: "Add App"))
            }
            Spacer()
            StackTrackedButton(.archivedApps, on: .googlePlayAppList) {
                homeCoordinator.navigateToArchivedApps(account: viewModel.uiState.account)
            } label: {
                Label(String(localized: "Archived"), systemImage: "archivebox")
            }
        }
    }
}

// MARK: - Add App Sheet

struct AddGooglePlayAppSheet: View {

    let isAdding: Bool
    let error: String?
    /// Who must have access to the app (service account or signed-in Google account).
    let footer: String
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    @State private var packageName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(String(localized: "Package Name")) {
                        TextField("com.example.app", text: $packageName)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                } header: {
                    Text("Application")
                } footer: {
                    Text(footer)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(String(localized: "Add App"))
            .trackScreen(.addGooglePlayApp)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .addGooglePlayApp) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(String(localized: "Add")) {
                            onAdd(packageName)
                        }
                        .disabled(packageName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
