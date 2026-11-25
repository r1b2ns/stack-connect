import SwiftUI

// MARK: - Factory

@MainActor
struct SettingsAccountsViewFactory {
    static func build() -> some View {
        SettingsAccountsEntry()
    }
}

// MARK: - Entry

private struct SettingsAccountsEntry: View {
    @StateObject private var coordinator = SettingsAccountsCoordinator()
    @StateObject private var viewModel = SettingsAccountsViewModel()

    var body: some View {
        SettingsAccountsView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

/// Settings › Accounts (plan `unified-accounts.md` §4): search, "Add account"
/// and "Import .scexport file", a per-store "Add", rows that open the account
/// detail, and "Delete all accounts" at the bottom.
struct SettingsAccountsView<ViewModel: SettingsAccountsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: SettingsAccountsCoordinator
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    private var listing: AccountsListingState { viewModel.uiState.listing }

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Accounts"))
            .trackScreen(.settingsAccounts)
            .searchable(
                text: $viewModel.uiState.listing.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search accounts", comment: "Accounts lists: placeholder of the search field.")
            )
            .trackSearch(query: listing.query, resultCount: listing.visibleCount, on: .settingsAccounts)
            .toolbar { buildToolbar() }
            .task { await viewModel.loadAccounts() }
            .fullScreenCover(item: $coordinator.wizardEntry) { entry in
                AccountWizardViewFactory.build(entry: entry) {
                    coordinator.dismissWizard()
                }
            }
            .alert(
                String(localized: "Delete All Accounts"),
                isPresented: $viewModel.uiState.showDeleteAllConfirmation
            ) {
                StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .settingsAccounts, role: .cancel) {}
                Button(String(localized: "Delete All"), role: .destructive) {
                    Task {
                        await viewModel.deleteAllAccounts()
                        homeCoordinator.popToRoot()
                    }
                }
            } message: {
                Text(String(localized: "This will permanently delete all accounts, apps, versions, and credentials from the app. This action cannot be undone."))
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if !listing.hasLoaded && listing.accounts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if listing.showsNoResults {
            AccountsNoResultsView(query: listing.query) {
                viewModel.clearSearch()
            }
        } else {
            buildList()
        }
    }

    private func buildList() -> some View {
        List {
            if !listing.isSearching {
                buildAddSection()
            }

            StackAccountGroupsSections(
                groups: listing.visibleGroups,
                onAdd: { provider in
                    coordinator.presentWizard(.kind(.provider(provider)))
                }
            ) { account in
                buildRow(account)
            }

            if listing.accounts.isEmpty {
                Section {
                    Text("No accounts yet. Add one, or import a file exported from another device.",
                         comment: "Settings › Accounts: shown under the add buttons when there are no accounts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !listing.accounts.isEmpty && !listing.isSearching {
                buildDeleteAllSection()
            }
        }
    }

    private func buildAddSection() -> some View {
        Section {
            StackTrackedButton(.addAccount, on: .settingsAccounts) {
                coordinator.presentWizard(.chooseKind)
            } label: {
                StackListRow(icon: "plus", iconColor: .blue, title: String(localized: "Add Account"))
            }
            .foregroundStyle(.primary)

            StackTrackedButton(.importAccount, on: .settingsAccounts) {
                coordinator.presentWizard(.kind(.importFile))
            } label: {
                StackListRow(
                    icon: "square.and.arrow.down",
                    iconColor: .gray,
                    title: String(localized: "Import .scexport File", comment: "Settings › Accounts: opens the account wizard on the import of a .scexport file.")
                )
            }
            .foregroundStyle(.primary)
        }
    }

    private func buildRow(_ account: AccountModel) -> some View {
        StackTrackedButton(.account, on: .settingsAccounts) {
            homeCoordinator.navigateToAccountDetail(account)
        } label: {
            StackAccountRow(account: account, status: listing.accountStatuses[account.id])
        }
        .foregroundStyle(.primary)
    }

    private func buildDeleteAllSection() -> some View {
        Section {
            StackTrackedButton(.deleteAllAccounts, on: .settingsAccounts, role: .destructive) {
                viewModel.uiState.showDeleteAllConfirmation = true
            } label: {
                Label(String(localized: "Delete All Accounts"), systemImage: "trash.fill")
            }
        } footer: {
            Text("Removes every account, its apps and its credentials from this device.",
                 comment: "Settings › Accounts: footer of Delete All Accounts.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            StackTrackedButton(.add, on: .settingsAccounts) {
                coordinator.presentWizard(.chooseKind)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(String(localized: "Add Account"))
        }
    }
}

// MARK: - ProviderType + Identifiable

extension ProviderType: Identifiable {
    var id: String { rawValue }
}
