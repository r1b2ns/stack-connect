import SwiftUI

// MARK: - Factory

@MainActor
struct UserAccessViewFactory {
    static func build(account: AccountModel) -> some View {
        UserAccessEntryView(account: account)
    }
}

// MARK: - Entry

private struct UserAccessEntryView: View {
    let account: AccountModel

    @StateObject private var viewModel: UserAccessViewModel

    init(account: AccountModel) {
        self.account = account
        _viewModel = StateObject(wrappedValue: UserAccessViewModel(account: account))
    }

    var body: some View {
        UserAccessView(viewModel: viewModel)
    }
}

// MARK: - View

struct UserAccessView<ViewModel: UserAccessViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator
    @Environment(\.analytics) private var analytics

    /// Tracks the first appearance so we can distinguish it (handled by `.task`)
    /// from a reappearance after popping back from `UserDetail`. On reappear we
    /// reload so a role change or a user deletion made on the detail screen is
    /// reflected here without requiring a manual pull-to-refresh.
    @State private var hasAppeared = false

    var body: some View {
        buildContent()
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search by name or email")
            )
            .trackSearch(query: viewModel.uiState.searchQuery, resultCount: viewModel.uiState.filteredUsers.count, on: .userAccess)
            .trackScreen(.userAccess)
            .task { await viewModel.load() }
            .onAppear {
                // Skip the initial appearance (`.task` already loaded); reload on
                // subsequent reappearances (returning from UserDetail).
                if hasAppeared {
                    Task { await viewModel.load() }
                } else {
                    hasAppeared = true
                }
            }
            .refreshable { await viewModel.refresh() }
            .sheet(isPresented: $viewModel.uiState.showInviteUser) {
                InviteUserSheet { email, firstName, lastName, roles, allApps, provisioning in
                    Task {
                        await viewModel.inviteUser(
                            email: email,
                            firstName: firstName,
                            lastName: lastName,
                            roles: roles,
                            allAppsVisible: allApps,
                            provisioningAllowed: provisioning
                        )
                    }
                } onCancel: {
                    viewModel.uiState.showInviteUser = false
                }
            }
            .alert(
                viewModel.uiState.confirmDeleteUser?.isPending == true
                    ? String(localized: "Cancel Invitation")
                    : String(localized: "Remove User"),
                isPresented: Binding(
                    get: { viewModel.uiState.confirmDeleteUser != nil },
                    set: { if !$0 { viewModel.uiState.confirmDeleteUser = nil } }
                )
            ) {
                Button(
                    viewModel.uiState.confirmDeleteUser?.isPending == true
                        ? String(localized: "Cancel Invitation")
                        : String(localized: "Remove"),
                    role: .destructive
                ) {
                    if let user = viewModel.uiState.confirmDeleteUser {
                        Task { await viewModel.deleteUser(user) }
                    }
                }
                StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .userAccess, role: .cancel) {}
            } message: {
                if let user = viewModel.uiState.confirmDeleteUser {
                    if user.isPending {
                        Text("Cancel the invitation sent to \(user.email ?? user.displayName)?")
                    } else {
                        Text("Are you sure you want to remove \(user.displayName)? This action cannot be undone.")
                    }
                }
            }
            .alert(
                String(localized: "Error"),
                isPresented: Binding(
                    get: { viewModel.uiState.inviteError != nil },
                    set: { if !$0 { viewModel.uiState.inviteError = nil } }
                )
            ) {
                StackTrackedButton(String(localized: "OK"), button: .ok, on: .userAccess, role: .cancel) {
                    viewModel.uiState.inviteError = nil
                }
            } message: {
                if let error = viewModel.uiState.inviteError {
                    Text(error)
                }
            }
            .alert(
                String(localized: "Cannot Remove User"),
                isPresented: Binding(
                    get: { viewModel.uiState.deleteError != nil },
                    set: { if !$0 { viewModel.uiState.deleteError = nil } }
                )
            ) {
                StackTrackedButton(String(localized: "OK"), button: .ok, on: .userAccess, role: .cancel) {
                    viewModel.uiState.deleteError = nil
                }
            } message: {
                if let error = viewModel.uiState.deleteError {
                    Text(error)
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.users.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            buildList()
        }
    }

    private func buildList() -> some View {
        List {
            // Filter strip — always visible
            buildFilterStrip()

            if viewModel.uiState.filteredUsers.isEmpty {
                buildEmptyRow()
            } else {
                buildUserRows()
            }
        }
    }

    @ViewBuilder
    private func buildEmptyRow() -> some View {
        Section {
            if !viewModel.uiState.searchQuery.isEmpty {
                ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
            } else if let error = viewModel.uiState.error {
                ContentUnavailableView {
                    Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                ContentUnavailableView {
                    Label(String(localized: "No Users"), systemImage: "person.slash")
                } description: {
                    Text("No users found matching the selected filter.")
                }
            }
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func buildUserRows() -> some View {
        Section {
                ForEach(viewModel.uiState.filteredUsers) { user in
                    StackTrackedButton(.user, on: .userAccess) {
                        homeCoordinator.navigateToUserDetail(user: user, account: viewModel.uiState.account)
                    } label: {
                        buildUserRow(user)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !user.roles.contains("ACCOUNT_HOLDER") {
                            StackTrackedButton(.delete, on: .userAccess, role: .destructive) {
                                viewModel.uiState.confirmDeleteUser = user
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Users")
                    Spacer()
                    Text("\(viewModel.uiState.filteredUsers.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    // MARK: - Filter Strip

    private func buildFilterStrip() -> some View {
        StackFilterChips(
            items: UserRoleFilter.allCases,
            selection: viewModel.uiState.selectedFilter,
            title: \.displayName
        ) { filter in
            analytics.track(.buttonTap(.filter, on: .userAccess))
            viewModel.uiState.selectedFilter = filter
        }
    }

    // MARK: - User Row

    private func buildUserRow(_ user: UserModel) -> some View {
        StackPersonRow(
            avatar: buildUserAvatar(user),
            title: user.displayName,
            subtitle: user.email,
            detail: user.rolesDisplayName,
            badge: user.isPending
                ? .init(title: String(localized: "Pending"), color: .orange)
                : (user.allAppsVisible ? .init(title: String(localized: "All Apps"), color: .blue) : nil)
        )
    }

    private func buildUserAvatar(_ user: UserModel) -> StackAvatar {
        let initials = [user.firstName?.prefix(1), user.lastName?.prefix(1)]
            .compactMap { $0.map(String.init) }
            .joined()
        return StackAvatar(initials: initials, tint: avatarColor(for: user.primaryRoleDisplayName))
    }

    private func avatarColor(for role: String) -> Color {
        switch role {
        case String(localized: "Account Holder"):   return .purple
        case String(localized: "Admin"):            return .red
        case String(localized: "Developer"):        return .blue
        case String(localized: "App Manager"):      return .green
        case String(localized: "Finance"):          return .orange
        case String(localized: "Marketing"):        return .pink
        case String(localized: "Sales"):            return .teal
        default:                                    return .gray
        }
    }

    // MARK: - Toolbar

}

// MARK: - Invite User Sheet

struct InviteUserSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var selectedRoles: Set<String> = []
    @State private var allAppsVisible = true
    @State private var provisioningAllowed = false

    let onInvite: (String, String, String, [String], Bool, Bool) -> Void
    let onCancel: () -> Void

    private let availableRoles: [(value: String, label: String)] = [
        ("ADMIN", String(localized: "Admin")),
        ("FINANCE", String(localized: "Finance")),
        ("SALES", String(localized: "Sales")),
        ("MARKETING", String(localized: "Marketing")),
        ("APP_MANAGER", String(localized: "App Manager")),
        ("DEVELOPER", String(localized: "Developer")),
        ("CUSTOMER_SUPPORT", String(localized: "Customer Support")),
    ]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: User Info
                Section {
                    TextField(String(localized: "Email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField(String(localized: "First Name"), text: $firstName)
                        .textContentType(.givenName)
                    TextField(String(localized: "Last Name"), text: $lastName)
                        .textContentType(.familyName)
                } header: {
                    Text("User Information")
                }

                // MARK: Roles
                Section {
                    ForEach(availableRoles, id: \.value) { role in
                        buildRoleToggleRow(value: role.value, label: role.label)
                    }
                } header: {
                    Text("Roles")
                } footer: {
                    Text("Select one or more roles for this user.")
                }

                // MARK: Access
                Section {
                    Toggle(String(localized: "Access to All Apps"), isOn: $allAppsVisible)
                    Toggle(String(localized: "Provisioning Allowed"), isOn: $provisioningAllowed)
                } header: {
                    Text("Access")
                } footer: {
                    Text("Control whether this user can see all apps and manage provisioning profiles.")
                }
            }
            .navigationTitle(String(localized: "Invite User"))
            .trackScreen(.inviteUser)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .inviteUser) {
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Send Invite")) {
                        onInvite(
                            email.trimmingCharacters(in: .whitespaces),
                            firstName.trimmingCharacters(in: .whitespaces),
                            lastName.trimmingCharacters(in: .whitespaces),
                            Array(selectedRoles),
                            allAppsVisible,
                            provisioningAllowed
                        )
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedRoles.isEmpty
    }

    @ViewBuilder
    private func buildRoleToggleRow(value: String, label: String) -> some View {
        StackTrackedButton(.toggleRole, on: .inviteUser) {
            if selectedRoles.contains(value) {
                selectedRoles.remove(value)
            } else {
                selectedRoles.insert(value)
            }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedRoles.contains(value) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accent)
                        .fontWeight(.semibold)
                }
            }
        }
    }

}
