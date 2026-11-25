import SwiftUI

// MARK: - Factory

@MainActor
struct AccountsListViewFactory {
    /// The unified accounts list (Home › Accounts; the split view's "Add
    /// Account" item, which opens the wizard right away with `initialEntry`).
    static func build(initialEntry: AccountWizardEntry? = nil) -> some View {
        AccountsListEntry(initialEntry: initialEntry)
    }
}

// MARK: - Entry

private struct AccountsListEntry: View {
    @StateObject private var coordinator: AccountsListCoordinator
    @StateObject private var viewModel = AccountsListViewModel()

    init(initialEntry: AccountWizardEntry?) {
        _coordinator = StateObject(wrappedValue: AccountsListCoordinator(initialEntry: initialEntry))
    }

    var body: some View {
        AccountsListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

/// Option A of plan `unified-accounts.md`: a grouped list in the iOS Settings
/// style, one section per store, searchable under the large title.
struct AccountsListView<ViewModel: AccountsListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: AccountsListCoordinator
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Accounts"))
            .navigationBarTitleDisplayMode(.large)
            .trackScreen(.accountsList)
            .searchable(
                text: $viewModel.uiState.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search accounts", comment: "Accounts lists: placeholder of the search field.")
            )
            .trackSearch(query: viewModel.uiState.query, resultCount: viewModel.uiState.visibleCount, on: .accountsList)
            .toolbar { buildToolbar() }
            .task {
                await viewModel.loadAccounts()
                coordinator.presentInitialEntryIfNeeded()
            }
            // The re-import deep link (expired imported account).
            .onReceive(ReimportRouter.shared.$pending.compactMap { $0 }) { request in
                ReimportRouter.shared.pending = nil
                Task {
                    if let entry = await viewModel.reconnectEntry(forAccountId: request.accountId) {
                        coordinator.presentWizard(entry)
                    }
                }
            }
            .fullScreenCover(item: $coordinator.wizardEntry) { entry in
                AccountWizardViewFactory.build(entry: entry) {
                    coordinator.dismissWizard()
                }
            }
            .alert(
                String(localized: "Account Expired"),
                isPresented: Binding(
                    get: { coordinator.expiredAccount != nil },
                    set: { if !$0 { coordinator.expiredAccount = nil } }
                ),
                presenting: coordinator.expiredAccount
            ) { account in
                StackTrackedButton(String(localized: "Re-import File"), button: .reimport, on: .accountsList) {
                    coordinator.presentWizard(.reconnect(account))
                }
                StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .accountsList, role: .cancel) {}
            } message: { account in
                Text("The account \"\(account.name)\" has expired. Re-import its file to keep using it.")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        let state = viewModel.uiState
        if !state.hasLoaded && state.accounts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.accounts.isEmpty {
            buildEmptyState()
        } else if state.showsNoResults {
            AccountsNoResultsView(query: state.query) {
                viewModel.clearSearch()
            }
        } else {
            buildList()
        }
    }

    private func buildEmptyState() -> some View {
        ContentUnavailableView {
            Label(String(localized: "No Accounts"), systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Tap + to add your first account.")
        } actions: {
            StackTrackedButton(String(localized: "Add Account"), button: .addAccount, on: .accountsList) {
                coordinator.presentWizard(.chooseKind)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func buildList() -> some View {
        List {
            StackAccountGroupsSections(groups: viewModel.uiState.visibleGroups) { account in
                buildRow(account)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func buildRow(_ account: AccountModel) -> some View {
        StackTrackedButton(.account, on: .accountsList) {
            open(account)
        } label: {
            StackAccountRow(account: account, status: viewModel.uiState.accountStatuses[account.id])
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await viewModel.deleteAccount(account) }
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }

    private func open(_ account: AccountModel) {
        guard !account.isExpired else {
            coordinator.presentExpiredAlert(for: account)
            return
        }
        switch account.providerType {
        case .apple:      homeCoordinator.navigateToAppList(account)
        case .firebase:   homeCoordinator.navigateToFirebaseProjectList(account)
        case .googlePlay: homeCoordinator.navigateToGooglePlayAppList(account)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            StackTrackedButton(.add, on: .accountsList) {
                coordinator.presentWizard(.chooseKind)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(String(localized: "Add Account"))
        }
    }
}

// MARK: - No results

/// The empty search result of the accounts lists, with a way out.
struct AccountsNoResultsView: View {
    let query: String
    let onClear: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No accounts for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”",
                     comment: "Accounts lists: the search found nothing. The placeholder is the search text.")
            } icon: {
                Image(systemName: "magnifyingglass")
            }
        } description: {
            Text("Search by account name, store or how it's connected.",
                 comment: "Accounts lists: hint under an empty search result.")
        } actions: {
            Button(String(localized: "Clear Search", comment: "Accounts lists: clears the search field.")) {
                onClear()
            }
        }
    }
}
