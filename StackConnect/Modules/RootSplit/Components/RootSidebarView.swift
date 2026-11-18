import SwiftUI

/// The split view sidebar: Dashboard, the release queues, the accounts of each
/// store (the selected account expands into its team tools) and Settings.
/// A `List(selection:)` with `.sidebar` style, so it gets the native selection
/// highlight, keyboard navigation and pointer hover on iPad and Mac.
struct RootSidebarView<ViewModel: RootSidebarViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Binding var selection: RootSidebarItem?

    var body: some View {
        List(selection: $selection) {
            buildDashboardRow()
            buildReleasesSection()
            ForEach(viewModel.uiState.providerSections) { section in
                buildProviderSection(section)
            }
            buildSettingsSection()
        }
        .listStyle(.sidebar)
        .navigationTitle("StackConnect")
    }

    // MARK: - Rows

    private func buildDashboardRow() -> some View {
        Label(
            String(localized: "Dashboard", comment: "Split view sidebar item and title of the iPad Home."),
            systemImage: "square.grid.2x2"
        )
        .tag(RootSidebarItem.dashboard)
    }

    private func buildReleasesSection() -> some View {
        Section(String(localized: "Releases")) {
            ForEach(RootReleaseQueue.allCases) { queue in
                Label(queue.title, systemImage: queue.systemImage)
                    .badge(viewModel.uiState.queueCounts[queue] ?? 0)
                    .tag(RootSidebarItem.releaseQueue(queue))
            }
            Label(String(localized: "Recent Reviews"), systemImage: "star.bubble")
                .tag(RootSidebarItem.recentReviews)
        }
    }

    private func buildProviderSection(_ section: RootSidebarProviderSection) -> some View {
        Section {
            if section.accounts.isEmpty {
                Label(String(localized: "Add Account"), systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
                    .tag(RootSidebarItem.addAccount(section.provider))
            }
            ForEach(section.accounts) { account in
                buildAccountRow(account)
                if selection?.accountId == account.id {
                    buildAccountSections(account)
                }
            }
        } header: {
            buildProviderHeader(section.provider)
        }
    }

    private func buildProviderHeader(_ provider: ProviderType) -> some View {
        HStack {
            Label(provider.displayName, systemImage: provider.iconName)
            Spacer()
            Button {
                selection = .addAccount(provider)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Add Account"))
            .help(String(localized: "Add Account"))
        }
    }

    private func buildAccountRow(_ account: AccountModel) -> some View {
        Label {
            HStack {
                Text(account.name)
                    .lineLimit(1)
                if account.isExpired {
                    StackCapsuleBadge(title: String(localized: "expired"), color: .red)
                }
            }
        } icon: {
            Image(systemName: account.providerType.iconName)
                .foregroundStyle(account.providerType.color)
        }
        .tag(RootSidebarItem.account(id: account.id, section: .apps))
        .contextMenu {
            ForEach(RootAccountSection.sections(for: account)) { section in
                Button {
                    selection = .account(id: account.id, section: section)
                } label: {
                    Label(section.title(for: account.providerType), systemImage: section.systemImage)
                }
            }
        }
    }

    /// Team tools of the selected account (the account row itself is "Apps").
    @ViewBuilder
    private func buildAccountSections(_ account: AccountModel) -> some View {
        ForEach(RootAccountSection.sections(for: account).filter { $0 != .apps }) { section in
            Label(section.title(for: account.providerType), systemImage: section.systemImage)
                .padding(.leading, 20)
                .tag(RootSidebarItem.account(id: account.id, section: section))
        }
    }

    private func buildSettingsSection() -> some View {
        Section {
            Label(String(localized: "Settings"), systemImage: "gearshape")
                .tag(RootSidebarItem.settings)
        }
    }
}
