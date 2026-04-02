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

struct SettingsAccountsView<ViewModel: SettingsAccountsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: SettingsAccountsCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Accounts"))
            .toolbar { buildToolbar() }
            .sheet(isPresented: $coordinator.showAddOptions) {
                buildAddOptionsSheet()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $coordinator.showProviderPicker) {
                buildProviderPickerSheet()
                    .presentationDetents([.medium])
            }
            .sheet(item: $coordinator.selectedProviderType) { providerType in
                AddAccountViewFactory.build(providerType: providerType) {
                    coordinator.dismissAddAccount()
                    Task { await viewModel.loadAccounts() }
                }
            }
            .sheet(isPresented: $coordinator.showImport) {
                buildImportSheet()
                    .presentationDetents([.medium])
            }
            .sheet(item: $coordinator.editingAccount) { account in
                buildEditAccountSheet(account)
                    .presentationDetents([.medium])
            }
            .task { await viewModel.loadAccounts() }
            .alert(
                String(localized: "Delete Account"),
                isPresented: $viewModel.uiState.showDeleteConfirmation,
                presenting: viewModel.uiState.accountToDelete
            ) { account in
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.uiState.accountToDelete = nil
                }
                Button(String(localized: "Delete"), role: .destructive) {
                    Task { await viewModel.deleteAccount(account) }
                    viewModel.uiState.accountToDelete = nil
                }
            } message: { account in
                Text("Are you sure you want to delete \"\(account.name)\"? This action cannot be undone.")
            }
            .sheet(isPresented: $viewModel.uiState.showExportShare) {
                if let fileURL = viewModel.uiState.exportFileURL {
                    ShareSheetView(activityItems: [fileURL])
                }
            }
            .sheet(item: $coordinator.exportingAccount) { account in
                ExportAccountView(
                    account: account,
                    onExport: { name, rules in
                        let url = viewModel.exportAccountWithRules(account: account, exportName: name, rules: rules)
                        coordinator.dismissExportAccount()
                        if let url {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                viewModel.uiState.exportFileURL = url
                                viewModel.uiState.showExportShare = true
                            }
                        }
                        return url
                    },
                    onDismiss: {
                        coordinator.dismissExportAccount()
                    }
                )
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && allAccountsEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if allAccountsEmpty {
            ContentUnavailableView {
                Label(
                    String(localized: "No Accounts"),
                    systemImage: "person.crop.circle.badge.plus"
                )
            } description: {
                Text("Tap + to add your first account.")
            }
        } else {
            buildList()
        }
    }

    private func buildList() -> some View {
        List {
            if !viewModel.uiState.appleAccounts.isEmpty {
                buildProviderSection(
                    title: ProviderType.apple.displayName,
                    icon: ProviderType.apple.iconName,
                    color: ProviderType.apple.color,
                    accounts: viewModel.uiState.appleAccounts
                )
            }

            if !viewModel.uiState.firebaseAccounts.isEmpty {
                buildProviderSection(
                    title: ProviderType.firebase.displayName,
                    icon: ProviderType.firebase.iconName,
                    color: ProviderType.firebase.color,
                    accounts: viewModel.uiState.firebaseAccounts
                )
            }

            if !viewModel.uiState.googlePlayAccounts.isEmpty {
                buildProviderSection(
                    title: ProviderType.googlePlay.displayName,
                    icon: ProviderType.googlePlay.iconName,
                    color: ProviderType.googlePlay.color,
                    accounts: viewModel.uiState.googlePlayAccounts
                )
            }
        }
    }

    private func buildProviderSection(
        title: String,
        icon: String,
        color: Color,
        accounts: [AccountModel]
    ) -> some View {
        Section {
            ForEach(accounts, id: \.id) { account in
                Button {
                    viewModel.uiState.editingName = account.name
                    coordinator.presentEditAccount(account)
                } label: {
                    HStack {
                        Text(account.name)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.uiState.accountToDelete = account
                        viewModel.uiState.showDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }

                    Button {
                        if account.providerType == .apple {
                            coordinator.presentExportAccount(account)
                        } else {
                            viewModel.uiState.exportFileURL = viewModel.exportAccountFile(account: account)
                            viewModel.uiState.showExportShare = true
                        }
                    } label: {
                        Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
            }
        }
    }

    // MARK: - Add Options Sheet

    private func buildAddOptionsSheet() -> some View {
        NavigationStack {
            List {
                Button {
                    coordinator.presentProviderPicker()
                } label: {
                    Label(String(localized: "Create New"), systemImage: "plus.circle.fill")
                }

                Button {
                    coordinator.presentImport()
                } label: {
                    Label(String(localized: "Import"), systemImage: "square.and.arrow.down.fill")
                }
            }
            .navigationTitle(String(localized: "Add Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        coordinator.showAddOptions = false
                    }
                }
            }
        }
    }

    // MARK: - Provider Picker Sheet

    private func buildProviderPickerSheet() -> some View {
        NavigationStack {
            List {
                Button {
                    coordinator.presentAddAccount(providerType: .apple)
                } label: {
                    Label {
                        Text(ProviderType.apple.displayName)
                    } icon: {
                        Image(systemName: ProviderType.apple.iconName)
                            .foregroundStyle(ProviderType.apple.color)
                    }
                }

                Button {
                    coordinator.presentAddAccount(providerType: .firebase)
                } label: {
                    Label {
                        Text(ProviderType.firebase.displayName)
                    } icon: {
                        Image(systemName: ProviderType.firebase.iconName)
                            .foregroundStyle(ProviderType.firebase.color)
                    }
                }

                Button {
                    coordinator.presentAddAccount(providerType: .googlePlay)
                } label: {
                    Label {
                        Text(ProviderType.googlePlay.displayName)
                    } icon: {
                        Image(systemName: ProviderType.googlePlay.iconName)
                            .foregroundStyle(ProviderType.googlePlay.color)
                    }
                }
            }
            .navigationTitle(String(localized: "Select Provider"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        coordinator.showProviderPicker = false
                    }
                }
            }
        }
    }

    // MARK: - Import Sheet

    private func buildImportSheet() -> some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "doc.badge.arrow.up.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.gray)

                Text(String(localized: "Import a JSON file containing your account credentials."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    // TODO: Implement JSON file import
                } label: {
                    Label(String(localized: "Import JSON File"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle(String(localized: "Import"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        coordinator.showImport = false
                    }
                }
            }
        }
    }

    // MARK: - Edit Account Sheet

    private func buildEditAccountSheet(_ account: AccountModel) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "Account Name"),
                        text: $viewModel.uiState.editingName
                    )
                    .textContentType(.name)
                } header: {
                    Text("Name")
                }

                Section {
                    if account.providerType == .apple {
                        Button {
                            coordinator.dismissEditAccount()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                coordinator.presentExportAccount(account)
                            }
                        } label: {
                            Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                        }
                    } else if let json = viewModel.exportAccountData(account: account) {
                        ShareLink(
                            item: json,
                            subject: Text(account.name),
                            message: Text("")
                        ) {
                            Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle(account.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        coordinator.dismissEditAccount()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        Task {
                            await viewModel.updateAccountName(
                                accountId: account.id,
                                newName: viewModel.uiState.editingName
                            )
                            coordinator.dismissEditAccount()
                        }
                    }
                    .disabled(viewModel.uiState.editingName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                coordinator.presentAddOptions()
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Helpers

    private var allAccountsEmpty: Bool {
        viewModel.uiState.appleAccounts.isEmpty &&
        viewModel.uiState.firebaseAccounts.isEmpty &&
        viewModel.uiState.googlePlayAccounts.isEmpty
    }
}

// MARK: - ProviderType + Identifiable (for sheet item)

extension ProviderType: Identifiable {
    var id: String { rawValue }
}

// MARK: - Share Sheet

private struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
