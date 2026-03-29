import SwiftUI

// MARK: - Factory

struct AppListViewFactory {
    static func build(account: AccountModel) -> some View {
        AppListEntry(account: account)
    }
}

// MARK: - Entry

private struct AppListEntry: View {
    let account: AccountModel

    @StateObject private var coordinator = AppListCoordinator()
    @StateObject private var viewModel: AppListViewModel

    init(account: AccountModel) {
        self.account = account
        _viewModel = StateObject(wrappedValue: AppListViewModel(account: account))
    }

    var body: some View {
        AppListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct AppListView<ViewModel: AppListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: AppListCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(viewModel.uiState.account.name)
            .toast(
                isPresented: $viewModel.uiState.showSyncToast,
                message: String(localized: "Syncing apps...")
            )
            .task { await viewModel.loadApps() }
            .refreshable { await viewModel.loadApps() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.apps.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.apps.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    private func buildEmptyState() -> some View {
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

    private func buildList() -> some View {
        List(viewModel.uiState.apps) { app in
            buildAppRow(app)
        }
    }

    private func buildAppRow(_ app: AppModel) -> some View {
        HStack {
            Image(systemName: "app.fill")
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(app.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
