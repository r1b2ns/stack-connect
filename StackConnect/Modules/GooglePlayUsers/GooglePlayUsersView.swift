import SwiftUI

// MARK: - View

/// The Users tab of a Google Play account (prototype 16). Hosted by the Play
/// app list's "Apps | Users" switch, which owns the ViewModel and the title.
struct GooglePlayUsersView<ViewModel: GooglePlayUsersViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.analytics) private var analytics

    /// The first appearance is loaded by `.task`; later ones (back from a
    /// user's detail) reload from the cache the detail keeps in step.
    @State private var hasAppeared = false

    var body: some View {
        buildContent()
            .trackScreen(.googlePlayUsers)
            .task { await viewModel.load() }
            .onAppear {
                if hasAppeared {
                    Task { await viewModel.reloadFromCache() }
                } else {
                    hasAppeared = true
                }
            }
            .refreshable { await viewModel.refresh() }
            .toast(isPresented: $viewModel.uiState.showSyncToast, message: String(localized: "Syncing users..."))
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        let state = viewModel.uiState
        if state.showsSetup {
            buildSetup()
        } else if state.isLoading && state.users.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.error, state.users.isEmpty {
            StackErrorContentView(
                message: error,
                reportContext: errorReportContext,
                onRetry: {
                    analytics.track(.buttonTap(.tryAgain, on: .googlePlayUsers))
                    Task { await viewModel.load() }
                }
            ) {
                if state.developerIdRejected {
                    Button(String(localized: "Change Developer ID")) { beginEditingDeveloperId() }
                }
            }
        } else {
            buildList()
        }
    }

    private var errorReportContext: ErrorReportContext {
        ErrorReportContext(screen: String(localized: "Users"), account: viewModel.uiState.account)
    }

    private func buildList() -> some View {
        List {
            if let error = viewModel.uiState.error {
                StackInlineErrorSection(message: error, reportContext: errorReportContext)
            }

            Section {
                ForEach(viewModel.uiState.users) { user in
                    buildRow(user)
                }
            } header: {
                Text("Users (\(viewModel.uiState.users.count))")
            }
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
    }

    // MARK: - Setup (plan U3)

    private func buildSetup() -> some View {
        List {
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

            Section {
                LabeledContent(String(localized: "Developer ID")) {
                    TextField("4829103756618820931", text: $viewModel.uiState.developerIdInput)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .monospacedDigit()
                        .submitLabel(.done)
                        .onSubmit { Task { await viewModel.saveDeveloperId() } }
                }
            } header: {
                Text("First-time setup")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = viewModel.uiState.developerIdError {
                        Text(error).foregroundStyle(.red)
                    }
                    Text("Google can't tell which developer account a service account belongs to: the ID is in Play Console › Settings › Developer account (and in every Play Console URL). The service account needs the “Admin (all permissions)” permission to manage users.")
                }
            }

            Section {
                Button {
                    Task { await viewModel.saveDeveloperId() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.uiState.isSavingDeveloperId {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.uiState.developerIdInput.trimmingCharacters(in: .whitespaces).isEmpty
                          || viewModel.uiState.isSavingDeveloperId)

                if viewModel.uiState.developerId != nil {
                    Button(String(localized: "Cancel"), role: .cancel) {
                        viewModel.uiState.isEditingDeveloperId = false
                        viewModel.uiState.developerIdError = nil
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func beginEditingDeveloperId() {
        analytics.track(.buttonTap(.editDeveloperId, on: .googlePlayUsers))
        viewModel.uiState.developerIdInput = viewModel.uiState.developerId ?? ""
        viewModel.uiState.developerIdError = nil
        viewModel.uiState.isEditingDeveloperId = true
    }
}
