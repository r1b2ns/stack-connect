import SwiftUI
import StackCrypto
import UniformTypeIdentifiers

// MARK: - Factory

@MainActor
struct AccountsListViewFactory {
    static func build(providerType: ProviderType) -> some View {
        AccountsListEntry(providerType: providerType)
    }
}

// MARK: - Entry

private struct AccountsListEntry: View {
    let providerType: ProviderType

    @StateObject private var coordinator: AccountsListCoordinator
    @StateObject private var viewModel: AccountsListViewModel

    init(providerType: ProviderType) {
        self.providerType = providerType
        _coordinator = StateObject(wrappedValue: AccountsListCoordinator(providerType: providerType))
        _viewModel = StateObject(wrappedValue: AccountsListViewModel(providerType: providerType))
    }

    var body: some View {
        AccountsListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct AccountsListView<ViewModel: AccountsListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: AccountsListCoordinator
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    @State private var importError = ""
    @State private var showImportError = false
    @State private var expiredAccessAccount: AccountModel?
    @State private var showExpiredAccessAlert = false

    var body: some View {
        buildContent()
            .navigationTitle(viewModel.uiState.providerType.displayName)
            .toolbar { buildToolbar() }
            .onReceive(ReimportRouter.shared.$pending.compactMap { $0 }) { request in
                guard request.providerType == viewModel.uiState.providerType else { return }
                viewModel.beginReimport(accountId: request.accountId)
                coordinator.showImport = true
                ReimportRouter.shared.pending = nil
            }
            .sheet(isPresented: $coordinator.showAddOptions) {
                buildAddOptionsSheet()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $coordinator.showAddAccount) {
                AddAccountViewFactory.build(providerType: viewModel.uiState.providerType) {
                    coordinator.showAddAccount = false
                    Task { await viewModel.loadAccounts() }
                }
            }
            .sheet(isPresented: $coordinator.showImport) {
                buildImportSheet()
                    .presentationDetents([.medium])
            }
            .alert(
                String(localized: "Import Error"),
                isPresented: $showImportError
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(importError)
            }
            .alert(
                String(localized: "Account Expired"),
                isPresented: $showExpiredAccessAlert,
                presenting: expiredAccessAccount
            ) { account in
                Button(String(localized: "Re-import File")) {
                    DeepLinkRouter.shared.open(DeepLink.reimport(accountId: account.id).url)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: { account in
                Text("The account \"\(account.name)\" has expired. Re-import its file to keep using it.")
            }
            .task { await viewModel.loadAccounts() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.accounts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.accounts.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    private func buildEmptyState() -> some View {
        ContentUnavailableView {
            Label(
                String(localized: "No Accounts"),
                systemImage: "person.crop.circle.badge.plus"
            )
        } description: {
            Text("Tap + to add your first account.")
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.accounts) { account in
                buildAccountRow(account)
            }
            .onDelete { offsets in
                Task { await viewModel.deleteAccount(at: offsets) }
            }
        }
    }

    private func buildAccountRow(_ account: AccountModel) -> some View {
        Button {
            guard !account.isExpired else {
                expiredAccessAccount = account
                showExpiredAccessAlert = true
                return
            }
            switch account.providerType {
            case .apple:
                homeCoordinator.navigateToAppList(account)
            case .firebase:
                homeCoordinator.navigateToFirebaseProjectList(account)
            case .googlePlay:
                homeCoordinator.navigateToGooglePlayAppList(account)
            }
        } label: {
            HStack {
                Image(systemName: account.providerType.iconName)
                    .foregroundStyle(account.providerType.color)
                    .frame(width: 32)

                Text(account.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if account.origin == .imported {
                    Text(String(localized: "imported"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Capsule())
                }

                if account.isExpired {
                    Text(String(localized: "expired"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Add Options Sheet

    private func buildAddOptionsSheet() -> some View {
        NavigationStack {
            List {
                Button {
                    coordinator.presentAddAccount()
                } label: {
                    Label(String(localized: "Create New"), systemImage: "plus.circle.fill")
                }

                if viewModel.uiState.providerType == .apple {
                    Button {
                        viewModel.uiState.replacingAccountId = nil
                        coordinator.presentImport()
                    } label: {
                        Label(String(localized: "Import"), systemImage: "square.and.arrow.down.fill")
                    }
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

    // MARK: - Import Sheet

    private func buildImportSheet() -> some View {
        AccountsListImportSheet(
            onImport: { url, password, customName in
                Task {
                    let error = await viewModel.importAccount(from: url, password: password, customName: customName)
                    if let error {
                        importError = error
                        showImportError = true
                    } else {
                        coordinator.showImport = false
                    }
                }
            },
            onCancel: {
                viewModel.uiState.replacingAccountId = nil
                coordinator.showImport = false
            }
        )
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
}

// MARK: - Import Sheet

private struct AccountsListImportSheet: View {

    let onImport: (URL, String, String?) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var showPasswordAlert = false
    @State private var showNameAlert = false
    @State private var showDecryptError = false
    @State private var decryptErrorMessage = ""
    @State private var password = ""
    @State private var customName = ""
    @State private var selectedURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "doc.badge.arrow.up.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.gray)

                Text(String(localized: "Import an encrypted .scexport file containing your account credentials."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    showFilePicker = true
                } label: {
                    Label(String(localized: "Import File"), systemImage: "square.and.arrow.down")
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
                        onCancel()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        selectedURL = url
                        password = ""
                        showPasswordAlert = true
                    }
                case .failure(let error):
                    Log.print.error("[Import] File picker error: \(error.localizedDescription)")
                }
            }
            .alert(
                String(localized: "Enter Password"),
                isPresented: $showPasswordAlert
            ) {
                SecureField(String(localized: "Password"), text: $password)
                Button(String(localized: "Cancel"), role: .cancel) {
                    selectedURL = nil
                    password = ""
                }
                Button(String(localized: "Decrypt")) {
                    tryDecrypt()
                }
            } message: {
                Text(String(localized: "Enter the password used to encrypt this file."))
            }
            .alert(
                String(localized: "Decryption Failed"),
                isPresented: $showDecryptError
            ) {
                Button(String(localized: "Try Again")) {
                    password = ""
                    showPasswordAlert = true
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    selectedURL = nil
                    password = ""
                }
            } message: {
                Text(decryptErrorMessage)
            }
            .alert(
                String(localized: "Import Account"),
                isPresented: $showNameAlert
            ) {
                TextField(String(localized: "Account Name"), text: $customName)
                Button(String(localized: "Cancel"), role: .cancel) {
                    selectedURL = nil
                    password = ""
                }
                Button(String(localized: "Import")) {
                    if let url = selectedURL {
                        onImport(url, password, customName)
                    }
                    selectedURL = nil
                    password = ""
                }
            } message: {
                Text(String(localized: "Choose a name for this account."))
            }
        }
    }

    private func tryDecrypt() {
        guard let url = selectedURL else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            decryptErrorMessage = String(localized: "Failed to read file.")
            showDecryptError = true
            return
        }

        do {
            let json = try AccountCrypto.decrypt(data: data, password: password)
            if let jsonData = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let name = dict["name"] as? String {
                customName = name
            } else {
                customName = ""
            }
            showNameAlert = true
        } catch {
            decryptErrorMessage = error.localizedDescription
            showDecryptError = true
        }
    }
}
