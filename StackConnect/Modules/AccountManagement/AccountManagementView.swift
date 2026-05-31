import SwiftUI

// MARK: - Factory

@MainActor
struct AccountManagementViewFactory {
    static func build(account: AccountModel) -> some View {
        AccountManagementEntry(account: account)
    }
}

// MARK: - Entry

private struct AccountManagementEntry: View {
    @StateObject private var coordinator = AccountManagementCoordinator()
    @StateObject private var viewModel: AccountManagementViewModel

    init(account: AccountModel) {
        _viewModel = StateObject(wrappedValue: AccountManagementViewModel(account: account))
    }

    var body: some View {
        AccountManagementView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct AccountManagementView<ViewModel: AccountManagementViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Manage Account"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                String(localized: "Delete Account"),
                isPresented: $viewModel.uiState.showDeleteConfirmation
            ) {
                Button(String(localized: "Cancel"), role: .cancel) {}
                Button(String(localized: "Delete"), role: .destructive) {
                    Task {
                        if await viewModel.deleteAccount() {
                            homeCoordinator.popToRoot()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to delete \"\(viewModel.uiState.account.name)\"? This action cannot be undone.")
            }
    }

    @ViewBuilder
    private func buildContent() -> some View {
        List {
            if viewModel.uiState.account.canView(.provisioning) {
                Section {
                    buildRow(
                        icon: "lock.shield",
                        title: String(localized: "Certificates"),
                        subtitle: String(localized: "Signing certificates for this account")
                    ) {
                        homeCoordinator.navigateToCertificatesList(viewModel.uiState.account)
                    }

                    buildRow(
                        icon: "ipod.and.applewatch",
                        title: String(localized: "Identifiers"),
                        subtitle: String(localized: "Bundle IDs and their capabilities")
                    ) {
                        homeCoordinator.navigateToIdentifiersList(viewModel.uiState.account)
                    }

                    buildRow(
                        icon: "iphone.gen3",
                        title: String(localized: "Devices"),
                        subtitle: String(localized: "Registered devices for testing")
                    ) {
                        homeCoordinator.navigateToDevicesList(viewModel.uiState.account)
                    }

                    buildRow(
                        icon: "doc.badge.gearshape",
                        title: String(localized: "Profiles"),
                        subtitle: String(localized: "Provisioning profiles for this account")
                    ) {
                        homeCoordinator.navigateToProfilesList(viewModel.uiState.account)
                    }
                }
            }

            Section {
                buildRow(
                    icon: "square.and.arrow.up",
                    title: String(localized: "Export Account"),
                    subtitle: String(localized: "Share credentials and rules with others")
                ) {
                    homeCoordinator.navigateToAccountSettings(viewModel.uiState.account)
                }
            }

            Section {
                Button(role: .destructive) {
                    viewModel.uiState.showDeleteConfirmation = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundStyle(.red)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Delete Account"))
                                .font(.body)
                                .foregroundStyle(.red)
                            Text(String(localized: "Remove this account and all its data"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    private func buildRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }
}
