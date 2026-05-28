import SwiftUI
import TipKit

// MARK: - Tips

struct AppListSwipeActionsTip: Tip {
    var title: Text {
        Text("Quick actions")
    }

    var message: Text? {
        Text("Swipe left on any app to archive it or mark it as favorite.")
    }

    var image: Image? {
        Image(systemName: "hand.draw.fill")
    }
}

// MARK: - Factory

@MainActor
struct AppListViewFactory {
    static func build(account: AccountModel) -> some View {
        AppListEntry(account: account)
    }
}

// MARK: - Tab

enum AppListTab: String, CaseIterable {
    case apps
    case usersAndAccess

    var displayName: String {
        switch self {
        case .apps:             return String(localized: "Apps")
        case .usersAndAccess:   return String(localized: "Users")
        }
    }
}

// MARK: - Entry

private struct AppListEntry: View {
    let account: AccountModel

    @StateObject private var coordinator = AppListCoordinator()
    @StateObject private var appListViewModel: AppListViewModel
    @StateObject private var userAccessViewModel: UserAccessViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator
    @State private var selectedTab: AppListTab = .apps

    init(account: AccountModel) {
        self.account = account
        _appListViewModel = StateObject(wrappedValue: AppListViewModel(account: account))
        _userAccessViewModel = StateObject(wrappedValue: UserAccessViewModel(account: account))
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
                AppListView(viewModel: appListViewModel)
            case .usersAndAccess:
                UserAccessView(viewModel: userAccessViewModel)
            }
        }
        .environmentObject(coordinator)
        .navigationTitle(account.name)
        .toolbar {
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

            ToolbarItem(placement: .topBarTrailing) {
                switch selectedTab {
                case .apps:
                    Button {
                        homeCoordinator.navigateToAccountManagement(account)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                case .usersAndAccess:
                    if account.canAdd(.users) {
                        Button {
                            userAccessViewModel.uiState.showInviteUser = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - View

struct AppListView<ViewModel: AppListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: AppListCoordinator
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    private let swipeActionsTip = AppListSwipeActionsTip()

    var body: some View {
        buildContent()
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search by name or bundle ID")
            )
            .toast(
                isPresented: $viewModel.uiState.showSyncToast,
                message: String(localized: "Syncing apps...")
            )
            .toolbar { buildBottomToolbar() }
            .task { await viewModel.loadApps() }
            .refreshable { await viewModel.loadApps() }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.apps.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.filteredApps.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if !viewModel.uiState.searchQuery.isEmpty {
            ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
        } else {
            ContentUnavailableView {
                Label(
                    String(localized: "No Apps"),
                    systemImage: "app.dashed"
                )
            } description: {
                if let error = viewModel.uiState.syncError {
                    Text(error)
                } else {
                    Text("No apps found for this account.")
                }
            }
        }
    }

    private func buildList() -> some View {
        List {
            TipView(swipeActionsTip)
                .listRowBackground(Color.white)
                .padding(.zero)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

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
            }
        }
    }

    private func buildAppButton(_ app: AppModel) -> some View {
        Button {
            homeCoordinator.navigateToAppDetail(app, account: viewModel.uiState.account)
        } label: {
            buildAppRow(app)
        }
        .foregroundStyle(.primary)
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

    private func buildAppRow(_ app: AppModel) -> some View {
        HStack(spacing: 12) {
            buildAppIcon(url: app.iconUrl.flatMap { URL(string: $0) })

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    if app.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                if let state = app.appStoreState {
                    buildStatusBadge(state: state, version: app.versionString)
                } else {
                    Text(app.bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func buildStatusBadge(state: AppStoreState, version: String?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(state.color))
                .frame(width: 6, height: 6)

            Text(state.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let version {
                Text("(\(version))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func statusColor(_ color: AppStoreStateColor) -> Color {
        switch color {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }

    // MARK: - App Icon

    private func buildAppIcon(url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        appIconPlaceholder
                    case .empty:
                        ProgressView()
                            .frame(width: 44, height: 44)
                    @unknown default:
                        appIconPlaceholder
                    }
                }
            } else {
                appIconPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var appIconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.blue.opacity(0.15))
            .overlay {
                Image(systemName: "app.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildBottomToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            Button {
                homeCoordinator.navigateToArchivedApps(account: viewModel.uiState.account)
            } label: {
                Label(String(localized: "Archived"), systemImage: "archivebox")
            }
        }
    }
}
