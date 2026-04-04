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

    var body: some View {
        buildContent()
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search by name or email")
            )
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
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
                Button(String(localized: "Cancel"), role: .cancel) {}
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
                Button(String(localized: "OK"), role: .cancel) {
                    viewModel.uiState.inviteError = nil
                }
            } message: {
                if let error = viewModel.uiState.inviteError {
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
                    buildUserRow(user)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !user.roles.contains("ACCOUNT_HOLDER") {
                                Button(role: .destructive) {
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(UserRoleFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.uiState.selectedFilter = filter
                        }
                    } label: {
                        Text(filter.displayName)
                            .font(.subheadline)
                            .fontWeight(viewModel.uiState.selectedFilter == filter ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                viewModel.uiState.selectedFilter == filter
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.systemGray6)
                            )
                            .foregroundStyle(
                                viewModel.uiState.selectedFilter == filter
                                    ? .accent
                                    : .secondary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - User Row

    private func buildUserRow(_ user: UserModel) -> some View {
        HStack(spacing: 12) {
            buildUserAvatar(user)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                if let email = user.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(user.rolesDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if user.isPending {
                    Text(String(localized: "Pending"))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                } else if user.allAppsVisible {
                    Text(String(localized: "All Apps"))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func buildUserAvatar(_ user: UserModel) -> some View {
        let initials = [user.firstName?.prefix(1), user.lastName?.prefix(1)]
            .compactMap { $0.map(String.init) }
            .joined()

        let color = avatarColor(for: user.primaryRoleDisplayName)

        return ZStack {
            Circle()
                .fill(color.opacity(0.15))

            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .foregroundStyle(color)
                    .font(.caption)
            } else {
                Text(initials)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
        }
        .frame(width: 36, height: 36)
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

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if viewModel.uiState.account.canAdd(.users) {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.uiState.showInviteUser = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - Invite User Sheet

struct InviteUserSheet: View {

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
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
        Button {
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
