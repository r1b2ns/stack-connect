import SwiftUI

// MARK: - Factory

@MainActor
struct SettingsViewFactory {
    static func build() -> some View {
        SettingsEntry()
    }

    /// Settings as the root of the compact Settings tab: its own
    /// `NavigationStack`, driven by `coordinator` (owned by `RootTabCoordinator`),
    /// so every screen reached from Settings pushes on this tab's stack.
    static func buildTabRoot(coordinator: HomeCoordinator) -> some View {
        SettingsTabRoot(coordinator: coordinator)
    }
}

// MARK: - Tab Root

private struct SettingsTabRoot: View {
    @ObservedObject var coordinator: HomeCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            SettingsEntry()
                .homeNavigationDestinations()
        }
        .environmentObject(coordinator)
    }
}

// MARK: - Entry

private struct SettingsEntry: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        SettingsView(viewModel: viewModel)
    }
}

// MARK: - View

struct SettingsView<ViewModel: SettingsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    @State private var showDeleteAllConfirmation = false

    var body: some View {
        List {
            buildGeneralSection()
            buildAppStoreConnectSection()
            buildPrivacySection()
            buildAboutSection()
            buildDangerSection()
            buildFooterSection()
        }
        .navigationTitle(String(localized: "Settings"))
        .trackScreen(.settings)
        .alert(
            String(localized: "Delete All Accounts"),
            isPresented: $showDeleteAllConfirmation
        ) {
            StackTrackedButton(String(localized: "Cancel"), button: .cancel, on: .settings, role: .cancel) {}
            Button(String(localized: "Delete All"), role: .destructive) {
                Task {
                    await viewModel.deleteAllAccounts()
                    homeCoordinator.popToRoot()
                }
            }
        } message: {
            Text(String(localized: "This will permanently delete all accounts, apps, versions, and credentials from the app. This action cannot be undone."))
        }
    }

    // MARK: - Sections

    private func buildGeneralSection() -> some View {
        Section {
            StackTrackedButton(.accounts, on: .settings) {
                homeCoordinator.navigateToSettingsAccounts()
            } label: {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 28)

                    Text(String(localized: "Accounts"))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func buildAppStoreConnectSection() -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.uiState.preReviewChecklistEnabled },
                set: { viewModel.setPreReviewChecklistEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Check list pre review"))
                        .foregroundStyle(.primary)

                    Text(String(localized: "Shows a checklist before submitting for Apple review"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "App Store Connect"))
        }
    }

    private func buildPrivacySection() -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.uiState.analyticsEnabled },
                set: { viewModel.setAnalyticsEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Share usage analytics"))
                        .foregroundStyle(.primary)

                    Text(String(localized: "Sends anonymous usage data to help improve StackConnect"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.uiState.showsNetworkAudit {
                buildNetworkAuditRow()
            }
        } header: {
            Text(String(localized: "Privacy"))
        } footer: {
            if viewModel.uiState.showsNetworkAudit {
                Text(String(localized: "Only screens visited and buttons tapped are collected. Account names, keys, bundle IDs and your app data are never sent. Check it in the Audit.", comment: "Settings › Privacy footer when the network audit is available."))
            } else {
                Text(String(localized: "Only screens visited and buttons tapped are collected. Account names, keys, bundle IDs and your app data are never sent."))
            }
        }
    }

    private func buildNetworkAuditRow() -> some View {
        StackTrackedButton(.networkAudit, on: .settings) {
            homeCoordinator.navigateToNetworkAudit()
        } label: {
            HStack {
                Image(systemName: "checklist.checked")
                    .foregroundStyle(.green)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(String(localized: "Audit", comment: "Settings › Privacy: row that opens the network audit."))
                            .foregroundStyle(.primary)
                        StackCapsuleBadge(title: String(localized: "NEW", comment: "Badge of a new feature."), color: .blue)
                    }
                    Text(String(localized: "See everything the app sends and receives", comment: "Settings › Privacy: subtitle of the Audit row."))
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

    private func buildAboutSection() -> some View {
        Section {
            StackTrackedButton(.supportProject, on: .settings) {
                homeCoordinator.navigateToTipJar()
            } label: {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .frame(width: 28)

                    Text(String(localized: "Support the Project"))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            Link(destination: URL(string: "https://github.com/r1b2ns/stack-connect")!) {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.purple)
                        .frame(width: 28)

                    Text(String(localized: "GitHub"))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .trackOpenURL(.github, on: .settings)

            StackTrackedButton(.license, on: .settings) {
                homeCoordinator.navigateToLicense()
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.gray)
                        .frame(width: 28)

                    Text(String(localized: "License"))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func buildDangerSection() -> some View {
        Section {
            StackTrackedButton(.deleteAllAccounts, on: .settings, role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                        .frame(width: 28)

                    Text(String(localized: "Delete All Accounts"))
                }
            }
        }
    }

    private func buildFooterSection() -> some View {
        Section {
        } footer: {
            HStack {
                Spacer()
                Text("StackConnect v\(viewModel.uiState.appVersion) (\(viewModel.uiState.buildNumber))")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }
}
