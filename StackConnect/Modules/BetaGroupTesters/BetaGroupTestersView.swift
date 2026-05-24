import SwiftUI

// MARK: - Factory

@MainActor
struct BetaGroupTestersViewFactory {
    static func build(group: BetaGroupModel, appId: String, account: AccountModel) -> some View {
        BetaGroupTestersEntryView(group: group, appId: appId, account: account)
    }
}

// MARK: - Entry

private struct BetaGroupTestersEntryView: View {
    let group: BetaGroupModel
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: BetaGroupTestersViewModel

    init(group: BetaGroupModel, appId: String, account: AccountModel) {
        self.group = group
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: BetaGroupTestersViewModel(group: group, appId: appId, account: account))
    }

    var body: some View {
        BetaGroupTestersView(viewModel: viewModel)
    }
}

// MARK: - View

struct BetaGroupTestersView<ViewModel: BetaGroupTestersViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Testers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { buildToolbar() }
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search testers")
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $viewModel.uiState.showAddTester) {
                if viewModel.uiState.group.isInternalGroup {
                    InternalTesterPickerSheet(
                        members: viewModel.uiState.teamMembers,
                        isLoading: viewModel.uiState.isLoadingTeamMembers,
                        isInviting: viewModel.uiState.isInvitingTesters
                    ) { selected in
                        Task { await viewModel.addTeamMembersAsTesters(selected) }
                    } onCancel: {
                        viewModel.uiState.showAddTester = false
                    }
                } else {
                    AddTesterSheet(
                        existingTesters: viewModel.uiState.testers,
                        isInviting: viewModel.uiState.isInvitingTesters,
                        onAdd: { email, firstName, lastName in
                            Task { await viewModel.addTester(email: email, firstName: firstName, lastName: lastName) }
                        },
                        onImportCSV: { rows in
                            Task { await viewModel.importCSVTesters(rows) }
                        },
                        onCancel: {
                            viewModel.uiState.showAddTester = false
                        }
                    )
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
            .alert(
                String(localized: "Remove Tester"),
                isPresented: Binding(
                    get: { viewModel.uiState.confirmRemoveTester != nil },
                    set: { if !$0 { viewModel.uiState.confirmRemoveTester = nil } }
                )
            ) {
                Button(String(localized: "Remove"), role: .destructive) {
                    if let tester = viewModel.uiState.confirmRemoveTester {
                        Task { await viewModel.removeTester(tester) }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                if let tester = viewModel.uiState.confirmRemoveTester {
                    Text("Remove \(tester.displayName) from this group?")
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
            .overlay {
                if viewModel.uiState.isRemovingTester || viewModel.uiState.isResendingInvite {
                    ZStack {
                        Color.black.opacity(0.1)
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    .ignoresSafeArea()
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.testers.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.testers.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Testers"), systemImage: "person.2.slash")
            } description: {
                Text("Tap the + button to add testers to this group.")
            }
        } else {
            buildTestersList()
        }
    }

    @ViewBuilder
    private func buildTestersList() -> some View {
        let filtered = viewModel.uiState.filteredTesters

        List {
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(filtered) { tester in
                        buildTesterRow(tester)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.uiState.confirmRemoveTester = tester
                                } label: {
                                    Label(String(localized: "Remove"), systemImage: "person.badge.minus")
                                }

                                if !viewModel.uiState.group.isInternalGroup && tester.state == "INVITED" {
                                    Button {
                                        Task { await viewModel.resendInvite(tester) }
                                    } label: {
                                        Label(String(localized: "Resend"), systemImage: "paperplane.fill")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(viewModel.uiState.group.name)
                        Spacer()
                        Text("\(filtered.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func buildTesterRow(_ tester: BetaTesterModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tester.stateIcon)
                .foregroundStyle(stateColor(tester.stateColor))
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(tester.displayName)
                    .font(.body)

                if let email = tester.email, tester.firstName != nil {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(tester.stateDisplayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(stateColor(tester.stateColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(stateColor(tester.stateColor).opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if viewModel.uiState.group.isInternalGroup {
                    Task { await viewModel.loadTeamMembers() }
                }
                viewModel.uiState.showAddTester = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Helpers

    private func stateColor(_ color: AppStoreStateColor) -> Color {
        switch color {
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .gray:   return .gray
        case .blue:   return .blue
        case .yellow: return .yellow
        }
    }
}
