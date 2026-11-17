import SwiftUI

// MARK: - Factory

@MainActor
struct GooglePlayUserDetailViewFactory {
    static func build(user: GooglePlayUserModel, account: AccountModel) -> some View {
        GooglePlayUserDetailEntry(user: user, account: account)
    }
}

// MARK: - Entry

private struct GooglePlayUserDetailEntry: View {
    @StateObject private var viewModel: GooglePlayUserDetailViewModel

    init(user: GooglePlayUserModel, account: AccountModel) {
        _viewModel = StateObject(wrappedValue: GooglePlayUserDetailViewModel(user: user, account: account))
    }

    var body: some View {
        GooglePlayUserDetailView(viewModel: viewModel)
    }
}

// MARK: - View

/// One Google Play user (plan U5, prototype 17).
struct GooglePlayUserDetailView<ViewModel: GooglePlayUserDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorShareRequest: StackErrorShareRequest?

    private var state: GooglePlayUserDetailUiState { viewModel.uiState }
    private var user: GooglePlayUserModel { state.user }

    var body: some View {
        List {
            buildHeaderSection()
            buildAccessSection()
            buildAccountPermissionsSection()
            buildOtherPermissionsSection()
            buildAppsSection()
            buildRemoveSection()
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(.googlePlayUserDetail)
        .task { await viewModel.load() }
        .toolbar { buildToolbar() }
        .disabled(state.isSaving)
        .sheet(isPresented: $viewModel.uiState.showExpiryEditor) {
            GooglePlayAccessExpirySheet(initial: state.draftExpiration) { expiration in
                viewModel.uiState.draftExpiration = expiration
            }
        }
        .sheet(item: $viewModel.uiState.grantEditor, onDismiss: {
            viewModel.uiState.grantEditorError = nil
        }) { request in
            buildAppPermissionsSheet(request)
        }
        .toast(message: $viewModel.uiState.toastMessage)
        .alert(
            user.accessState.isPendingInvitation ? String(localized: "Cancel Invitation") : String(localized: "Remove User"),
            isPresented: $viewModel.uiState.confirmRemove
        ) {
            Button(user.accessState.isPendingInvitation ? String(localized: "Cancel Invitation") : String(localized: "Remove"),
                   role: .destructive) {
                Task {
                    if await viewModel.remove() { dismiss() }
                }
            }
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayUserDetail, role: .cancel) {}
        } message: {
            Text("\(user.email) loses access to this Play Console developer account right away.")
        }
        .alert(
            String(localized: "Remove Access"),
            isPresented: Binding(
                get: { state.confirmRemoveGrant != nil },
                set: { if !$0 { viewModel.uiState.confirmRemoveGrant = nil } }
            ),
            presenting: state.confirmRemoveGrant
        ) { grant in
            Button(String(localized: "Remove"), role: .destructive) {
                Task { _ = await viewModel.removeGrant(grant) }
            }
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayUserDetail, role: .cancel) {}
        } message: { grant in
            Text("\(user.email) loses access to \(appName(grant.packageName)).")
        }
        .alert(
            String(localized: "Can't Make This Change"),
            isPresented: Binding(
                get: { state.refusalMessage != nil },
                set: { if !$0 { viewModel.uiState.refusalMessage = nil } }
            ),
            presenting: state.refusalMessage
        ) { _ in
            StackTrackedButton(String(localized: "OK"), button: .ok, on: .googlePlayUserDetail, role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert(
            String(localized: "Error"),
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { viewModel.uiState.errorMessage = nil } }
            ),
            presenting: state.errorMessage
        ) { message in
            StackTrackedButton(String(localized: "OK"), button: .ok, on: .googlePlayUserDetail, role: .cancel) {}
            StackErrorShareAlertButton(
                message: message,
                context: errorReportContext(screen: user.displayName, details: state.errorDetails),
                request: $errorShareRequest
            )
        } message: { message in
            Text(message)
        }
        .stackErrorShareSheet($errorShareRequest)
    }

    /// Share Error context of this screen (or of its App Permissions sheet).
    private func errorReportContext(screen: String, details: [String]) -> ErrorReportContext {
        ErrorReportContext(screen: screen, account: state.account, technicalDetails: details)
    }

    // MARK: - App Permissions sheet (plan U7)

    private func buildAppPermissionsSheet(_ request: GooglePlayGrantEditorRequest) -> some View {
        let grant = request.packageName.flatMap { user.grant(for: $0) }
        return GooglePlayAppPermissionsSheet(
            form: GooglePlayGrantForm(
                packageName: request.packageName,
                values: request.permissions,
                accountValues: user.developerAccountPermissions
            ),
            apps: state.availableAppsForNewGrant,
            editedApp: request.packageName.flatMap { state.app(for: $0) },
            onSave: { packageName, values in
                await viewModel.saveGrant(packageName: packageName, permissions: values)
            },
            onRemove: grant.map { grant in
                { await viewModel.removeGrant(grant) }
            },
            error: state.grantEditorError?.message,
            errorReportContext: errorReportContext(
                screen: String(localized: "App Permissions"),
                details: state.grantEditorError?.technicalDetails ?? []
            )
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        if state.access.canEdit {
            ToolbarItem(placement: .confirmationAction) {
                if state.isSaving {
                    ProgressView()
                } else {
                    Button(String(localized: "Save")) {
                        Task { await viewModel.save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!state.hasChanges)
                }
            }
        }
    }

    // MARK: - Header

    private func buildHeaderSection() -> some View {
        Section {
            StackPersonHeader(
                avatar: user.avatar(size: 56),
                title: user.displayName,
                subtitle: user.accessState.isPendingInvitation ? nil : user.email,
                badge: user.stateBadge
            )
        } footer: {
            if user.partial {
                Text("Google returned only part of this user's access (they also have access this service account can't see). Edit them in Play Console.")
            } else if state.isSelf {
                Text("This is the service account StackConnect uses for this account: it can't be removed here and keeps its Admin permission.")
            }
        }
    }

    // MARK: - Access

    private func buildAccessSection() -> some View {
        Section {
            GooglePlayAccessExpiryRow(expiration: state.draftExpiration, isEnabled: state.access.editRefusal(for: user) == nil) {
                viewModel.uiState.showExpiryEditor = true
            }

            Toggle(GooglePlayPermissionCatalog.adminName, isOn: Binding(
                get: { state.draftIsAdmin },
                set: { viewModel.setAdmin($0) }
            ))
            .disabled(!state.canEditAccountPermissions)
        } header: {
            Text("Access")
        } footer: {
            if state.draftIsAdmin {
                Text("Admin grants every permission for every app, including managing users.")
            }
        }
    }

    // MARK: - Account permissions

    private func buildAccountPermissionsSection() -> some View {
        Section {
            GooglePlayAccountPermissionRows(
                values: state.draftAccountPermissions,
                isEditable: state.canEditAccountPermissions
            ) { permission, isOn in
                viewModel.setAccountPermission(permission, isOn: isOn)
            }
        } header: {
            Text("Account Permissions · All Apps")
        } footer: {
            if state.access.isScoped {
                Text("Account-wide permissions reach every app, so this account (limited to some apps) can't change them.")
            }
        }
    }

    @ViewBuilder
    private func buildOtherPermissionsSection() -> some View {
        let unknown = GooglePlayPermissionCatalog.unknownValues(in: state.draftAccountPermissions)
        if !unknown.isEmpty {
            Section {
                ForEach(unknown, id: \.self) { value in
                    LabeledContent(GooglePlayPermissionCatalog.displayName(forUnknown: value)) {
                        Image(systemName: "checkmark").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Other", comment: "Google Play permissions StackConnect doesn't know (kept as they are).")
            } footer: {
                Text("Permissions StackConnect doesn't know yet. They are kept when you save.")
            }
        }
    }

    // MARK: - App permissions

    @ViewBuilder
    private func buildAppsSection() -> some View {
        Section {
            if user.grants.isEmpty {
                Text(user.hasAllAppsAccess
                     ? String(localized: "No app-specific permissions: the account permissions above apply to every app.")
                     : String(localized: "No app access yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(state.sortedGrants) { grant in
                buildGrantRow(grant)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if state.access.grantRefusal(for: user, packageName: grant.packageName) == nil {
                            Button(role: .destructive) {
                                viewModel.requestRemoveGrant(grant)
                            } label: {
                                Label(String(localized: "Remove Access"), systemImage: "minus.circle")
                            }
                        }
                    }
            }
        } header: {
            HStack {
                Text("App Permissions (\(user.grants.count))")
                Spacer()
                if state.canAddGrant {
                    Button(String(localized: "Add App")) {
                        viewModel.uiState.grantEditor = GooglePlayGrantEditorRequest(packageName: nil, permissions: [])
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            }
        } footer: {
            if !user.grants.isEmpty {
                Text("Swipe an app to remove this user's access to it.")
            }
        }
    }

    private func buildGrantRow(_ grant: GooglePlayGrantModel) -> some View {
        let editable = state.access.grantRefusal(for: user, packageName: grant.packageName) == nil
        return Button {
            viewModel.uiState.grantEditor = GooglePlayGrantEditorRequest(packageName: grant.packageName, permissions: grant.appLevelPermissions)
        } label: {
            HStack(spacing: 12) {
                GooglePlayAppIconView(app: state.app(for: grant.packageName), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName(grant.packageName))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(grant.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editable)
    }

    private func appName(_ packageName: String) -> String {
        state.app(for: packageName)?.displayName ?? packageName
    }

    // MARK: - Remove

    @ViewBuilder
    private func buildRemoveSection() -> some View {
        if state.canRemove {
            Section {
                Button(role: .destructive) {
                    viewModel.requestRemove()
                } label: {
                    Text(user.accessState.isPendingInvitation ? String(localized: "Cancel Invitation") : String(localized: "Remove User"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - App icon

/// A Play app's icon, or the green Play tile while it has none.
struct GooglePlayAppIconView: View {
    let app: GooglePlayAppItem?
    var size: CGFloat = 32

    var body: some View {
        StackAppIcon(url: app?.iconURL, size: size, cornerRadius: size * 0.225) {
            StackIconTile(systemName: "play.fill", color: .green, size: size, font: .system(size: size * 0.45))
        }
    }
}
