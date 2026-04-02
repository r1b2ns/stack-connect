import SwiftUI

// MARK: - Factory

@MainActor
struct AccountsListViewFactory {
    static func build(providerType: ProviderType) -> some View {
        AccountsListEntry(providerType: providerType)
    }
}

// MARK: - Entry

private struct AccountsListEntry: View {
    let providerType: ProviderType

    @StateObject private var coordinator: AccountsListCoordinator
    @StateObject private var viewModel: AccountsListViewModel

    init(providerType: ProviderType) {
        self.providerType = providerType
        _coordinator = StateObject(wrappedValue: AccountsListCoordinator(providerType: providerType))
        _viewModel = StateObject(wrappedValue: AccountsListViewModel(providerType: providerType))
    }

    var body: some View {
        AccountsListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct AccountsListView<ViewModel: AccountsListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: AccountsListCoordinator
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(viewModel.uiState.providerType.displayName)
            .toolbar { buildToolbar() }
            .sheet(isPresented: $coordinator.showAddAccount) {
                AddAccountViewFactory.build(providerType: viewModel.uiState.providerType) {
                    coordinator.showAddAccount = false
                    Task { await viewModel.loadAccounts() }
                }
            }
            .task { await viewModel.loadAccounts() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.accounts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.accounts.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    private func buildEmptyState() -> some View {
        ContentUnavailableView {
            Label(
                String(localized: "No Accounts"),
                systemImage: "person.crop.circle.badge.plus"
            )
        } description: {
            Text("Tap + to add your first account.")
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.accounts) { account in
                buildAccountRow(account)
            }
            .onDelete { offsets in
                Task { await viewModel.deleteAccount(at: offsets) }
            }
        }
    }

    private func buildAccountRow(_ account: AccountModel) -> some View {
        Button {
            switch account.providerType {
            case .apple:
                homeCoordinator.navigateToAppList(account)
            case .firebase:
                homeCoordinator.navigateToFirebaseProjectList(account)
            case .googlePlay:
                homeCoordinator.navigateToGooglePlayAppList(account)
            }
        } label: {
            HStack {
                Image(systemName: account.providerType.iconName)
                    .foregroundStyle(account.providerType.color)
                    .frame(width: 32)

                Text(account.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                coordinator.presentAddAccount()
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}
