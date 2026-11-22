import SwiftUI

// MARK: - Entry

/// Built by `ArchivedAppsViewFactory` for a Google Play account.
struct GooglePlayArchivedAppsEntry: View {
    @StateObject private var viewModel: GooglePlayArchivedAppsViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: GooglePlayArchivedAppsViewModel(account: account))
    }

    var body: some View {
        GooglePlayArchivedAppsView(viewModel: viewModel)
    }
}

// MARK: - View

/// The Google Play counterpart of `ArchivedAppsView`: same title, search,
/// empty state and "Unarchive" swipe action, with the Play app rows.
struct GooglePlayArchivedAppsView<ViewModel: GooglePlayArchivedAppsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Archived Apps"))
            .trackScreen(.googlePlayArchivedApps)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search by name or package")
            )
            .trackSearch(query: viewModel.uiState.searchQuery, resultCount: viewModel.uiState.filteredApps.count, on: .googlePlayArchivedApps)
            .task { await viewModel.loadApps() }
            .refreshable { await viewModel.refresh() }
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
                Label(String(localized: "No Archived Apps"), systemImage: "archivebox")
            } description: {
                Text("Archived apps will appear here.")
            }
        }
    }

    private func buildList() -> some View {
        List(viewModel.uiState.filteredApps) { app in
            StackTrackedButton(.app, on: .googlePlayArchivedApps) {
                homeCoordinator.navigateToGooglePlayAppDetail(app, account: viewModel.uiState.account)
            } label: {
                buildAppRow(app)
            }
            .foregroundStyle(.primary)
            .contextMenu { buildUnarchiveButton(app) }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                buildUnarchiveButton(app)
                    .tint(.blue)
            }
        }
    }

    private func buildUnarchiveButton(_ app: GooglePlayAppItem) -> some View {
        Button {
            Task { await viewModel.unarchive(app: app) }
        } label: {
            Label(String(localized: "Unarchive"), systemImage: "arrow.uturn.backward")
        }
    }

    private func buildAppRow(_ app: GooglePlayAppItem) -> some View {
        HStack(spacing: 12) {
            StackAppIcon(url: app.iconURL, size: 44, cornerRadius: 10) {
                StackIconTile(systemName: "play.fill", color: .green, size: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if app.title != nil {
                    Text(app.packageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
