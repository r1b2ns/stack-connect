import SwiftUI

// MARK: - Factory

/// Users and Access for the wide split view (prototype #s6): a sortable
/// `Table` with the user's detail in an inspector beside it.
@MainActor
struct UserAccessTableViewFactory {
    static func build(account: AccountModel) -> some View {
        UserAccessTableEntry(account: account)
    }
}

private struct UserAccessTableEntry: View {
    @StateObject private var viewModel: UserAccessViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: UserAccessViewModel(account: account))
    }

    var body: some View {
        UserAccessTableView(viewModel: viewModel)
    }
}

// MARK: - Sorting

extension UserModel {
    /// "All apps" or a blank, for the table's Apps column (sorts all-apps first).
    var appsColumnText: String {
        allAppsVisible ? String(localized: "All Apps") : "–"
    }

    var statusColumnText: String {
        isPending ? String(localized: "Pending") : String(localized: "Active")
    }
}

// MARK: - View

struct UserAccessTableView<ViewModel: UserAccessViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.analytics) private var analytics

    @State private var selection: UserModel.ID?
    @State private var sortOrder = [KeyPathComparator(\UserModel.displayName)]

    private var account: AccountModel { viewModel.uiState.account }

    private var rows: [UserModel] {
        viewModel.uiState.filteredUsers.sorted(using: sortOrder)
    }

    private var selectedUser: UserModel? {
        selection.flatMap { id in viewModel.uiState.users.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            buildFilterBar()
            buildTable()
        }
        .navigationTitle(String(localized: "Users and Access"))
        .searchable(text: $viewModel.uiState.searchQuery, prompt: String(localized: "Search by name or email"))
        .trackScreen(.userAccess)
        .toolbar { buildToolbar() }
        .inspector(isPresented: inspectorBinding) {
            buildInspector()
                .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
        // Edits and removals made in the inspector show once it closes.
        .onChange(of: selection) { old, new in
            if old != nil && new == nil {
                Task { await viewModel.load() }
            }
        }
        .userAccessPresentations(viewModel: viewModel)
    }

    // MARK: - Filter

    private func buildFilterBar() -> some View {
        StackFilterChips(
            items: UserRoleFilter.allCases,
            selection: viewModel.uiState.selectedFilter,
            title: \.displayName
        ) { filter in
            analytics.track(.buttonTap(.filter, on: .userAccess))
            viewModel.uiState.selectedFilter = filter
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Table

    @ViewBuilder
    private func buildTable() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.users.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Users"), systemImage: "person.slash")
            } description: {
                if let error = viewModel.uiState.error {
                    Text(error)
                } else {
                    Text("No users found matching the selected filter.")
                }
            }
        } else {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(String(localized: "Name"), value: \.displayName) { user in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                        if let email = user.email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn(String(localized: "Role"), value: \.rolesDisplayName)
                TableColumn(String(localized: "Apps"), value: \.appsColumnText)
                TableColumn(String(localized: "Status"), value: \.statusColumnText) { user in
                    StackCapsuleBadge(
                        title: user.statusColumnText,
                        color: user.isPending ? .orange : .green
                    )
                }
            }
            .contextMenu(forSelectionType: UserModel.ID.self) { ids in
                if let user = ids.first.flatMap({ id in rows.first { $0.id == id } }),
                   !user.roles.contains(UserRoleCatalog.accountHolder),
                   account.canDelete(.users) {
                    Button(role: .destructive) {
                        viewModel.uiState.confirmDeleteUser = user
                    } label: {
                        Label(
                            user.isPending ? String(localized: "Cancel Invitation") : String(localized: "Remove User"),
                            systemImage: "trash"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Inspector

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { if !$0 { selection = nil } }
        )
    }

    @ViewBuilder
    private func buildInspector() -> some View {
        if let user = selectedUser {
            NavigationStack {
                UserDetailViewFactory.build(user: user, account: account)
                    .id(user.id)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) { selection = nil }
                        }
                    }
            }
        } else {
            ContentUnavailableView(
                String(localized: "Nothing Selected", comment: "Split view detail column placeholder title."),
                systemImage: "person.crop.circle"
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if account.canAdd(.users) {
            ToolbarItem(placement: .primaryAction) {
                StackTrackedButton(.inviteUser, on: .userAccess) {
                    viewModel.uiState.showInviteUser = true
                } label: {
                    Label(String(localized: "Invite User"), systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
