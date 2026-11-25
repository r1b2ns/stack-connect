import SwiftUI

// MARK: - Factory

@MainActor
struct SettingsAccountDetailViewFactory {
    static func build(account: AccountModel) -> some View {
        SettingsAccountDetailEntry(account: account)
    }
}

// MARK: - Entry

private struct SettingsAccountDetailEntry: View {
    @StateObject private var coordinator = SettingsAccountDetailCoordinator()
    @StateObject private var viewModel: SettingsAccountDetailViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: SettingsAccountDetailViewModel(account: account))
    }

    var body: some View {
        SettingsAccountDetailView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

/// An account in Settings › Accounts: status header, "Sign in again" when
/// its sign-in is disconnected, its details, Export and Delete.
struct SettingsAccountDetailView<ViewModel: SettingsAccountDetailViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: SettingsAccountDetailCoordinator
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    private var account: AccountModel { viewModel.uiState.account }

    var body: some View {
        List {
            buildStatusSection()
            buildInfoSection()
            buildManageSection()
            buildExportSection()
            buildDeleteSection()
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(.accountDetail)
        // `.task` runs again when coming back from Account Settings.
        .task { await viewModel.load() }
        .fullScreenCover(item: $coordinator.wizardEntry) { entry in
            AccountWizardViewFactory.build(entry: entry) {
                coordinator.dismissWizard()
                Task { await viewModel.load() }
            }
        }
        .sheet(isPresented: $coordinator.isShowingExport) {
            buildExportSheet()
        }
        .sheet(item: $viewModel.uiState.shareItem) { item in
            AccountExportShareSheet(activityItems: [item.url])
        }
        .sheet(item: $coordinator.exportFeedback) { feedback in
            FeedbackScreen(
                type: feedback.type,
                image: feedback.image,
                title: feedback.title,
                message: feedback.message,
                onDismiss: { coordinator.dismissExportFeedback() }
            )
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            String(localized: "Delete Account"),
            isPresented: $viewModel.uiState.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                Task {
                    if await viewModel.deleteAccount() {
                        homeCoordinator.popToRoot()
                    }
                }
            }
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .accountDetail, role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(account.name)\"? This action cannot be undone.")
        }
    }

    // MARK: - Status

    private func buildStatusSection() -> some View {
        Section {
            HStack(spacing: 14) {
                StackIconTile(systemName: account.providerType.iconName, color: account.providerType.color, size: 48, font: .title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.headline)
                    Text(account.providerType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let status = viewModel.uiState.status {
                        StackAccountStatusBadge(status: status)
                    } else {
                        // An HStack, not a `Label`: inside a `List` row a Label
                        // reserves the list's icon column, leaving a wide gap.
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .accessibilityHidden(true)
                            Text(String(localized: "Connected", comment: "Account detail: the account works."))
                        }
                        .font(.caption)
                        .foregroundStyle(.green)
                    }
                }
            }
            .padding(.vertical, 4)

            if let status = viewModel.uiState.status {
                ForEach(status.issues, id: \.self) { issue in
                    Text(issue.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let method = viewModel.uiState.reconnectMethod {
                StackTrackedButton(.signInAgain, on: .accountDetail) {
                    coordinator.presentReconnect(account)
                } label: {
                    Label(
                        method == .scexportFile ? String(localized: "Re-import File") : String(localized: "Sign In Again", comment: "Account wizard: reconnects a Google account on Google's page."),
                        systemImage: method == .scexportFile ? "square.and.arrow.down" : "arrow.clockwise"
                    )
                }
            }
        }
    }

    // MARK: - Info

    private func buildInfoSection() -> some View {
        Section {
            LabeledContent(String(localized: "Provider"), value: account.providerType.displayName)
            LabeledContent(String(localized: "Connection", comment: "Account wizard review: how the account connects."), value: account.connection.title)
            if let role = account.displayedRole {
                LabeledContent(String(localized: "Role", comment: "Label of an account's or a user's App Store Connect role (account detail, account settings, account wizard review, users table)."),
                               value: role.displayName)
            }
            LabeledContent(String(localized: "Origin"), value: account.origin == .created ? String(localized: "Created") : String(localized: "Imported"))
            LabeledContent(String(localized: "Created"), value: account.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let expirationDate = account.expirationDate {
                LabeledContent(String(localized: "Expiration Date"), value: expirationDate.formatted(date: .abbreviated, time: .shortened))
            }
            if account.providerType == .googlePlay {
                LabeledContent(String(localized: "Developer ID"), value: account.googlePlayDeveloperId ?? String(localized: "Not set"))
            }
        } header: {
            Text(String(localized: "Account"))
        }
    }

    private func buildManageSection() -> some View {
        Section {
            StackTrackedButton(.edit, on: .accountDetail) {
                homeCoordinator.navigateToAccountSettings(account)
            } label: {
                StackListRow(
                    icon: "slider.horizontal.3",
                    iconColor: .blue,
                    title: String(localized: "Account Settings"),
                    subtitle: String(localized: "Name, role and permissions", comment: "Account detail: what Account Settings changes.")
                )
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Export

    @ViewBuilder
    private func buildExportSection() -> some View {
        if let reason = viewModel.uiState.exportUnavailableReason {
            Section {
                Label(String(localized: "Export Account"), systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
                    .accessibilityHint(Text(reason))
            } footer: {
                Text(reason)
            }
        } else {
            Section {
                StackTrackedButton(.export, on: .accountDetail) {
                    coordinator.presentExport()
                } label: {
                    Label(String(localized: "Export Account"), systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text(String(localized: "Share credentials and rules with others"))
            }
        }
    }

    private func buildExportSheet() -> some View {
        ExportAccountView(
            account: account,
            loadApps: { await viewModel.appsForExport() },
            onExport: { name, rules, password, expirationDate, appsBundles in
                let url = viewModel.exportAccountWithRules(exportName: name, rules: rules, password: password, expirationDate: expirationDate, appsBundles: appsBundles)
                coordinator.dismissExport()
                if let url {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        viewModel.uiState.shareItem = ShareableFileURL(url: url)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        coordinator.presentExportFeedback(ExportFeedback(
                            type: .success,
                            image: "checkmark.seal.fill",
                            title: String(localized: "Export Successful"),
                            message: String(localized: "The account \"\(name)\" was exported successfully. Share the encrypted file with your team.")
                        ))
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        coordinator.presentExportFeedback(ExportFeedback(
                            type: .error,
                            image: "xmark.seal.fill",
                            title: String(localized: "Export Failed"),
                            message: String(localized: "Unable to export the account \"\(name)\". Please check your credentials and try again.")
                        ))
                    }
                }
                return url
            },
            onDismiss: { coordinator.dismissExport() }
        )
    }

    // MARK: - Delete

    private func buildDeleteSection() -> some View {
        Section {
            StackTrackedButton(.delete, on: .accountDetail, role: .destructive) {
                viewModel.uiState.showDeleteConfirmation = true
            } label: {
                Label(String(localized: "Delete Account"), systemImage: "trash")
            }
        } footer: {
            Text(String(localized: "Remove this account and all its data"))
        }
    }
}

// MARK: - Share Sheet

/// The share sheet of an exported `.scexport` file. The file is deleted once
/// the sheet closes: it must not linger in the temporary directory.
private struct AccountExportShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            for case let url as URL in activityItems where url.isFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
