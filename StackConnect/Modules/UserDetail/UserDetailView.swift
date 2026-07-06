import SwiftUI
import StackProtocols

// MARK: - Factory

@MainActor
struct UserDetailViewFactory {
    static func build(user: UserModel, account: AccountModel) -> some View {
        UserDetailEntry(user: user, account: account)
    }
}

// MARK: - Entry

private struct UserDetailEntry: View {
    let user: UserModel
    let account: AccountModel

    @StateObject private var coordinator = UserDetailCoordinator()
    @StateObject private var viewModel: UserDetailViewModel

    init(user: UserModel, account: AccountModel) {
        self.user = user
        self.account = account
        _viewModel = StateObject(wrappedValue: UserDetailViewModel(user: user, account: account))
    }

    var body: some View {
        UserDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct UserDetailView<ViewModel: UserDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    private var user: UserModel { viewModel.uiState.user }

    var body: some View {
        List {
            buildHeaderSection()
            buildRolesSection()
            buildAccessSection()
            buildVisibleAppsSection()
            buildInvitationSection()
            buildDangerSection()
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadVisibleApps() }
        .sheet(isPresented: $viewModel.uiState.showRoleEditor) {
            RoleEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.uiState.showResourcesEditor) {
            ResourcesEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.uiState.showVisibleAppsEditor) {
            VisibleAppsEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.uiState.showPermissions) {
            PermissionsSheet(roles: user.roles)
                .presentationDetents([.medium, .large])
        }
        .alert(
            user.isPending
                ? String(localized: "Cancel Invitation")
                : String(localized: "Remove User"),
            isPresented: $viewModel.uiState.confirmDelete
        ) {
            Button(
                user.isPending
                    ? String(localized: "Cancel Invitation")
                    : String(localized: "Remove"),
                role: .destructive
            ) {
                Task {
                    let ok = await viewModel.deleteUser()
                    if ok { dismiss() }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            if user.isPending {
                Text("Cancel the invitation sent to \(user.email ?? user.displayName)?")
            } else {
                Text("Are you sure you want to remove \(user.displayName)? This action cannot be undone.")
            }
        }
        .alert(
            String(localized: "Error"),
            isPresented: Binding(
                get: { viewModel.uiState.errorMessage != nil },
                set: { if !$0 { viewModel.uiState.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                viewModel.uiState.errorMessage = nil
            }
        } message: {
            if let error = viewModel.uiState.errorMessage {
                Text(error)
            }
        }
        .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Header

    private func buildHeaderSection() -> some View {
        Section {
            HStack(spacing: 16) {
                buildAvatar()

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let email = user.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if user.isPending {
                        buildPendingBadge()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func buildPendingBadge() -> some View {
        Text(String(localized: "Pending"))
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
            .padding(.top, 2)
    }

    private func buildAvatar() -> some View {
        let initials = [user.firstName?.prefix(1), user.lastName?.prefix(1)]
            .compactMap { $0.map(String.init) }
            .joined()

        return ZStack {
            Circle()
                .fill(Color.blue.opacity(0.15))

            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            } else {
                Text(initials)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 56, height: 56)
    }

    // MARK: - Roles

    @ViewBuilder
    private func buildRolesSection() -> some View {
        Section {
            if user.roles.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(user.roles, id: \.self) { role in
                    Text(UserModel.formatRole(role))
                }
            }

            Button {
                viewModel.uiState.showPermissions = true
            } label: {
                Label(String(localized: "What do these permissions allow?"), systemImage: "info.circle")
                    .font(.subheadline)
            }
        } header: {
            HStack {
                Text("Roles")
                Spacer()
                if viewModel.uiState.canEditRole {
                    Button(String(localized: "Edit")) {
                        viewModel.uiState.showRoleEditor = true
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        } footer: {
            if viewModel.uiState.isAccountHolder {
                Text("The Account Holder's role cannot be changed.")
            } else if viewModel.uiState.isPending {
                Text("Pending invitations can't be edited. Cancel and re-invite to change roles.")
            }
        }
    }

    // MARK: - Access

    private func buildAccessSection() -> some View {
        Section {
            buildAccessRow(
                title: String(localized: "Access to All Apps"),
                isOn: user.allAppsVisible
            )
            buildAccessRow(
                title: String(localized: "Provisioning Allowed"),
                isOn: user.provisioningAllowed
            )
        } header: {
            HStack {
                Text("Access")
                Spacer()
                if viewModel.uiState.canEdit {
                    Button(String(localized: "Edit")) {
                        viewModel.uiState.showResourcesEditor = true
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
    }

    private func buildAccessRow(title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)

            Spacer()

            Image(systemName: isOn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isOn ? .green : .secondary)
        }
    }

    // MARK: - Visible Apps

    @ViewBuilder
    private func buildVisibleAppsSection() -> some View {
        // Only relevant for an active user scoped to specific apps.
        if viewModel.uiState.canEditVisibleApps {
            Section {
                if viewModel.uiState.isLoadingVisibleApps {
                    HStack {
                        ProgressView()
                        Text(String(localized: "Loading apps…"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text(String(localized: "Visible Apps"))
                        Spacer()
                        Text("\(viewModel.uiState.selectedAppIds.count)")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        viewModel.uiState.showVisibleAppsEditor = true
                    } label: {
                        Label(String(localized: "Edit Visible Apps"), systemImage: "square.grid.2x2")
                    }
                }
            } header: {
                Text("Visible Apps")
            } footer: {
                Text("This user can only see the selected apps.")
            }
        }
    }

    // MARK: - Invitation

    @ViewBuilder
    private func buildInvitationSection() -> some View {
        if user.isPending {
            Section {
                HStack {
                    Text(String(localized: "Invitation Expires"))

                    Spacer()

                    if let expirationDate = user.expirationDate {
                        Text(expirationDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Invitation")
            }
        }
    }

    // MARK: - Danger Zone

    @ViewBuilder
    private func buildDangerSection() -> some View {
        if viewModel.uiState.canDelete {
            Section {
                Button(role: .destructive) {
                    viewModel.uiState.confirmDelete = true
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.uiState.isSaving {
                            ProgressView()
                        } else {
                            Label(
                                user.isPending
                                    ? String(localized: "Cancel Invitation")
                                    : String(localized: "Remove User"),
                                systemImage: user.isPending ? "envelope.badge.shield.half.filled" : "person.badge.minus"
                            )
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.uiState.isSaving)
            }
        }
    }
}

// MARK: - Role Editor Sheet

private struct RoleEditorSheet<ViewModel: UserDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(UserRoleCatalog.assignablePrimaryRoles, id: \.self) { role in
                        Button {
                            // Reconciles dependent add-ons / provisioning so an
                            // invalid combination can never be submitted.
                            viewModel.selectPrimaryRole(role)
                        } label: {
                            HStack {
                                Text(UserModel.formatRole(role))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.uiState.selectedPrimaryRole == role {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Primary Role")
                } footer: {
                    Text("Choose a single primary role for this user.")
                }
            }
            .navigationTitle(String(localized: "Edit Role"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        Task { await viewModel.saveRole() }
                    }
                    .disabled(viewModel.uiState.selectedPrimaryRole == nil || viewModel.uiState.isSaving)
                }
            }
        }
    }
}

// MARK: - Resources Editor Sheet

private struct ResourcesEditorSheet<ViewModel: UserDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    /// Add-on resources valid for the currently selected base role (empty for
    /// non-app-management roles). Drives whether the section is shown at all.
    private var allowedResources: [String] {
        UserRoleCatalog.allowedResources(for: viewModel.uiState.selectedPrimaryRole)
    }

    /// Whether the selected base role may carry the `provisioningAllowed` flag.
    private var supportsProvisioning: Bool {
        UserRoleCatalog.supportsProvisioning(viewModel.uiState.selectedPrimaryRole)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Additional resources & provisioning are only valid for the
                // app-management base roles — hide them entirely otherwise so an
                // invalid combination can't be assembled.
                if !allowedResources.isEmpty {
                    Section {
                        ForEach(allowedResources, id: \.self) { resource in
                            Toggle(isOn: bindingForResource(resource)) {
                                Text(UserModel.formatRole(resource))
                            }
                        }
                    } header: {
                        Text("Additional Resources")
                    } footer: {
                        Text("Extra capabilities layered on top of the primary role.")
                    }
                }

                Section {
                    Toggle(String(localized: "Access to All Apps"), isOn: $viewModel.uiState.allAppsVisible)
                    if supportsProvisioning {
                        Toggle(String(localized: "Provisioning Allowed"), isOn: $viewModel.uiState.provisioningAllowed)
                    }
                } header: {
                    Text("Access")
                } footer: {
                    Text("Turn off Access to All Apps to scope this user to specific apps.")
                }
            }
            .navigationTitle(String(localized: "Edit Access"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        Task {
                            let ok = await viewModel.saveResources()
                            // If the user just enabled app-scoping, refresh the picker source.
                            if ok { await viewModel.loadVisibleApps() }
                        }
                    }
                    .disabled(viewModel.uiState.isSaving)
                }
            }
        }
    }

    private func bindingForResource(_ resource: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.uiState.selectedResources.contains(resource) },
            set: { isOn in
                if isOn {
                    viewModel.uiState.selectedResources.insert(resource)
                } else {
                    viewModel.uiState.selectedResources.remove(resource)
                }
            }
        )
    }
}

// MARK: - Visible Apps Editor Sheet

private struct VisibleAppsEditorSheet<ViewModel: UserDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.uiState.isLoadingVisibleApps && viewModel.uiState.availableApps.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.uiState.availableApps.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Apps"), systemImage: "square.grid.2x2")
                    } description: {
                        Text("There are no apps to assign to this user.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(viewModel.uiState.availableApps) { app in
                                Button {
                                    toggle(app.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name)
                                                .foregroundStyle(.primary)
                                            Text(app.bundleId)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if viewModel.uiState.selectedAppIds.contains(app.id) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.accent)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                }
                            }
                        } footer: {
                            Text("Selected: \(viewModel.uiState.selectedAppIds.count)")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Visible Apps"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        Task { await viewModel.saveVisibleApps() }
                    }
                    .disabled(viewModel.uiState.isSaving)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if viewModel.uiState.selectedAppIds.contains(id) {
            viewModel.uiState.selectedAppIds.remove(id)
        } else {
            viewModel.uiState.selectedAppIds.insert(id)
        }
    }
}

// MARK: - Permissions Sheet

private struct PermissionsSheet: View {

    let roles: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if roles.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Roles"), systemImage: "person.crop.circle.badge.questionmark")
                    } description: {
                        Text("This user has no roles assigned.")
                    }
                } else {
                    ForEach(roles, id: \.self) { role in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(UserModel.formatRole(role))
                                .font(.headline)
                            Text(UserRoleCatalog.permissionDescription(for: role))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(String(localized: "Permissions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }
}
