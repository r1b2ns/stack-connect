import SwiftUI

// MARK: - View

/// The Users tab of a Google Play account (prototype 16). Hosted by the Play
/// app list's "Apps | Users" switch, which owns the ViewModel and the title.
struct GooglePlayUsersView<ViewModel: GooglePlayUsersViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator
    @Environment(\.analytics) private var analytics
    @State private var errorShareRequest: StackErrorShareRequest?

    var body: some View {
        buildContent()
            .trackScreen(.googlePlayUsers)
            .task {
                // SwiftUI restarts `.task` when the tab comes back from a
                // pushed user detail: re-read the cache that screen keeps in
                // step instead of asking Google again (pull to refresh does).
                if viewModel.uiState.hasLoaded {
                    await viewModel.reloadFromCache()
                } else {
                    await viewModel.load()
                }
            }
            .refreshable { await viewModel.refresh() }
            .toast(isPresented: $viewModel.uiState.showSyncToast, message: String(localized: "Syncing users..."))
            .toast(message: $viewModel.uiState.toastMessage)
            .sheet(isPresented: $viewModel.uiState.showInvite) {
                GooglePlayInviteUserSheet(
                    apps: viewModel.uiState.apps,
                    allowsAccountPermissions: viewModel.uiState.access.canInviteWithAccountPermissions,
                    errorReportContext: ErrorReportContext(
                        screen: String(localized: "Invite User"),
                        account: viewModel.uiState.account,
                        technicalDetails: viewModel.uiState.inviteErrorDetails
                    )
                ) { form in
                    await viewModel.invite(form)
                }
            }
            .alert(
                viewModel.uiState.confirmRemove?.accessState.isPendingInvitation == true
                    ? String(localized: "Cancel Invitation")
                    : String(localized: "Remove User"),
                isPresented: isPresented(\.confirmRemove),
                presenting: viewModel.uiState.confirmRemove
            ) { user in
                StackTrackedButton(user.accessState.isPendingInvitation ? String(localized: "Cancel Invitation") : String(localized: "Remove"),
                                   button: .confirmDelete, on: .googlePlayUsers, role: .destructive) {
                    Task { await viewModel.remove(user) }
                }
                StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayUsers, role: .cancel) {}
            } message: { user in
                Text("\(user.email) loses access to this Play Console developer account right away.")
            }
            .alert(
                String(localized: "Resend Invitation"),
                isPresented: isPresented(\.confirmResend),
                presenting: viewModel.uiState.confirmResend
            ) { user in
                StackTrackedButton(String(localized: "Resend"), button: .confirmResendInvite, on: .googlePlayUsers) {
                    Task { await viewModel.resend(user) }
                }
                StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .googlePlayUsers, role: .cancel) {}
            } message: { user in
                Text("Google Play can't resend an invitation. StackConnect removes the expired one and invites \(user.email) again with the same permissions and app access.")
            }
            .alert(
                String(localized: "Can't Make This Change"),
                isPresented: isPresented(\.refusalMessage),
                presenting: viewModel.uiState.refusalMessage
            ) { _ in
                StackTrackedButton(String(localized: "OK"), button: .ok, on: .googlePlayUsers, role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert(
                String(localized: "Error"),
                isPresented: isPresented(\.actionError),
                presenting: viewModel.uiState.actionError
            ) { message in
                StackTrackedButton(String(localized: "OK"), button: .ok, on: .googlePlayUsers, role: .cancel) {}
                StackErrorShareAlertButton(
                    message: message,
                    context: errorReportContext.withTechnicalDetails(viewModel.uiState.actionErrorDetails),
                    request: $errorShareRequest
                )
            } message: { message in
                Text(message)
            }
            .stackErrorShareSheet($errorShareRequest)
    }

    /// A Bool binding over an optional piece of state, cleared on dismiss.
    private func isPresented<Value>(_ keyPath: WritableKeyPath<GooglePlayUsersUiState, Value?>) -> Binding<Bool> {
        Binding(
            get: { viewModel.uiState[keyPath: keyPath] != nil },
            set: { if !$0 { viewModel.uiState[keyPath: keyPath] = nil } }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        let state = viewModel.uiState
        if state.showsSetup {
            buildSetup()
        } else if state.users.isEmpty && (state.isLoading || !state.hasLoaded) {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.error, state.users.isEmpty {
            // Network, offline, server: the developer ID isn't in question.
            StackErrorContentView(
                message: error,
                reportContext: errorReportContext.withTechnicalDetails(state.errorDetails),
                // The Retry tap is tracked by `StackErrorContentView`.
                onRetry: { Task { await viewModel.load() } }
            )
        } else {
            buildList()
                .searchable(
                    text: $viewModel.uiState.searchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: String(localized: "Search by name or email")
                )
                .trackSearch(query: viewModel.uiState.searchQuery, resultCount: viewModel.uiState.filteredUsers.count, on: .googlePlayUsers)
        }
    }

    private func retry() {
        analytics.track(.buttonTap(.tryAgain, on: .googlePlayUsers))
        Task { await viewModel.load() }
    }

    private var errorReportContext: ErrorReportContext {
        ErrorReportContext(screen: String(localized: "Users"), account: viewModel.uiState.account)
    }

    private func buildList() -> some View {
        List {
            StackFilterChips(
                items: GooglePlayUsersFilter.allCases,
                selection: viewModel.uiState.selectedFilter,
                title: \.title
            ) { filter in
                analytics.track(.buttonTap(.filter, on: .googlePlayUsers))
                viewModel.uiState.selectedFilter = filter
            }

            if let error = viewModel.uiState.error {
                StackInlineErrorSection(
                    message: error,
                    reportContext: errorReportContext.withTechnicalDetails(viewModel.uiState.errorDetails)
                )
            }

            let users = viewModel.uiState.filteredUsers
            if users.isEmpty {
                buildEmptySection()
            } else {
                Section {
                    ForEach(users) { user in
                        StackTrackedButton(.user, on: .googlePlayUsers) {
                            homeCoordinator.navigateToGooglePlayUserDetail(user, account: viewModel.uiState.account)
                        } label: {
                            buildRow(user)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { buildSwipeActions(user) }
                    }
                } header: {
                    Text("Users (\(users.count))")
                } footer: {
                    Text("Swipe a user to Remove them, or to Resend an invitation that expired. Changes apply to your Play Console developer account right away.")
                }
            }
        }
    }

    @ViewBuilder
    private func buildEmptySection() -> some View {
        Section {
            if !viewModel.uiState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
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

    /// Remove for everyone the account may remove; Resend on an expired
    /// invitation. Refusals (self, scope) explain themselves when tapped.
    @ViewBuilder
    private func buildSwipeActions(_ user: GooglePlayUserModel) -> some View {
        let access = viewModel.uiState.access
        if access.canDelete {
            Button(role: .destructive) {
                viewModel.requestRemove(user)
            } label: {
                Label(String(localized: "Remove"), systemImage: "person.badge.minus")
            }
        }
        if user.accessState == .invitationExpired, access.canInvite, access.canDelete {
            Button {
                viewModel.requestResend(user)
            } label: {
                Label(String(localized: "Resend"), systemImage: "envelope.arrow.triangle.branch")
            }
            .tint(.blue)
        }
    }

    func buildRow(_ user: GooglePlayUserModel) -> some View {
        StackPersonRow(
            avatar: user.avatar(),
            title: user.displayName,
            subtitle: user.listSubtitle,
            detail: GooglePlayPermissionCatalog.summary(for: user),
            badge: user.listBadge
        )
        .overlay(alignment: .trailing) {
            if viewModel.uiState.workingEmail == user.email {
                ProgressView().padding(.trailing, 24)
            }
        }
    }

    // MARK: - Setup (plan U3)

    /// The one-field form: first-time setup (no developer ID yet), or the
    /// stored ID rejected by the last load — then pre-filled with it, under
    /// the load error (with its Share Error) and with a Retry.
    private func buildSetup() -> some View {
        let state = viewModel.uiState
        let rejected = state.developerIdRejected
        let isBusy = state.isSavingDeveloperId || state.isSyncing
        return List {
            if rejected {
                if let error = state.error {
                    StackInlineErrorSection(
                        message: error,
                        reportContext: errorReportContext.withTechnicalDetails(state.errorDetails)
                    )
                }
            } else {
                buildSetupIntro()
            }

            Section {
                LabeledContent(String(localized: "Developer ID")) {
                    TextField(String(localized: "Developer ID"), text: $viewModel.uiState.developerIdInput,
                              prompt: Text(verbatim: "4829103756618820931"))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .monospacedDigit()
                        .submitLabel(.done)
                        .onSubmit { Task { await viewModel.saveDeveloperId() } }
                }
            } header: {
                rejected ? Text("Developer ID") : Text("First-time setup")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = state.developerIdError {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(error)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StackErrorShareLink(
                                message: error,
                                context: errorReportContext.withTechnicalDetails(state.developerIdErrorDetails),
                                style: .icon
                            )
                        }
                    }
                    Text("Google can't tell which developer account a service account belongs to: the ID is in Play Console › Settings › Developer account (and in every Play Console URL). The service account needs the “Admin (all permissions)” permission to manage users.")
                }
            }

            Section {
                Button {
                    Task { await viewModel.saveDeveloperId() }
                } label: {
                    buildFormButtonLabel(String(localized: "Save"), isWorking: state.isSavingDeveloperId)
                        .fontWeight(.semibold)
                }
                .disabled(state.developerIdInput.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)

                if rejected {
                    Button(action: retry) {
                        buildFormButtonLabel(String(localized: "Retry"),
                                             isWorking: state.isSyncing && !state.isSavingDeveloperId)
                    }
                    .disabled(isBusy)
                }
            }
        }
    }

    private func buildSetupIntro() -> some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "person.2.badge.key")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Manage Play Console users")
                    .font(.headline)
                Text("Enter this account's Developer ID once to list, invite and edit the people who can access your Play Console.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    /// A centered form button title, or a spinner while it runs.
    private func buildFormButtonLabel(_ title: String, isWorking: Bool) -> some View {
        HStack {
            Spacer()
            if isWorking {
                ProgressView()
            } else {
                Text(title)
            }
            Spacer()
        }
    }
}
