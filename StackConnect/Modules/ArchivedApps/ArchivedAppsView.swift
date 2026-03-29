import SwiftUI

// MARK: - Factory

struct ArchivedAppsViewFactory {
    static func build(account: AccountModel) -> some View {
        ArchivedAppsEntry(account: account)
    }
}

// MARK: - Entry

private struct ArchivedAppsEntry: View {
    let account: AccountModel

    @StateObject private var viewModel: ArchivedAppsViewModel

    init(account: AccountModel) {
        self.account = account
        _viewModel = StateObject(wrappedValue: ArchivedAppsViewModel(account: account))
    }

    var body: some View {
        ArchivedAppsView(viewModel: viewModel)
    }
}

// MARK: - View

struct ArchivedAppsView<ViewModel: ArchivedAppsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Archived Apps"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search by name or bundle ID")
            )
            .task { await viewModel.loadApps() }
            .refreshable { await viewModel.loadApps() }
            .overlay(alignment: .bottom) {
                if viewModel.uiState.isSyncing {
                    buildSyncingIndicator()
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: viewModel.uiState.isSyncing)
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
                    String(localized: "No Archived Apps"),
                    systemImage: "archivebox"
                )
            } description: {
                Text("Archived apps will appear here.")
            }
        }
    }

    private func buildList() -> some View {
        List(viewModel.uiState.filteredApps) { app in
            Button {
                homeCoordinator.navigateToAppDetail(app, account: viewModel.uiState.account)
            } label: {
                buildAppRow(app)
            }
            .foregroundStyle(.primary)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    Task { await viewModel.unarchive(app: app) }
                } label: {
                    Label(String(localized: "Unarchive"), systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
        }
    }

    private func buildAppRow(_ app: AppModel) -> some View {
        HStack(spacing: 12) {
            buildAppIcon(url: app.iconUrl.flatMap { URL(string: $0) })

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

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

    // MARK: - Sync Indicator

    private func buildSyncingIndicator() -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(String(localized: "Syncing..."))
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}
