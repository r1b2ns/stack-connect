import SwiftUI

// MARK: - Factory

@MainActor
struct VersionListViewFactory {
    static func build(appId: String, platform: AppPlatform, account: AccountModel) -> some View {
        VersionListEntry(appId: appId, platform: platform, account: account)
    }
}

// MARK: - Entry

private struct VersionListEntry: View {
    let appId: String
    let platform: AppPlatform
    let account: AccountModel

    @StateObject private var coordinator = VersionListCoordinator()
    @StateObject private var viewModel: VersionListViewModel

    init(appId: String, platform: AppPlatform, account: AccountModel) {
        self.appId = appId
        self.platform = platform
        self.account = account
        _viewModel = StateObject(wrappedValue: VersionListViewModel(appId: appId, platform: platform, account: account))
    }

    var body: some View {
        VersionListView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct VersionListView<ViewModel: VersionListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(viewModel.uiState.platform.displayName)
            .toast(
                isPresented: $viewModel.uiState.showSyncToast,
                message: String(localized: "Syncing versions...")
            )
            .task { await viewModel.loadVersions() }
            .refreshable { await viewModel.loadVersions() }
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.versions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.versions.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Versions"), systemImage: "doc.text.magnifyingglass")
            } description: {
                if let error = viewModel.uiState.syncError {
                    Text(error)
                } else {
                    Text("No versions found for this platform.")
                }
            }
        } else {
            buildList()
        }
    }

    private func buildList() -> some View {
        List(viewModel.uiState.versions) { version in
            Button {
                homeCoordinator.navigateToVersionDetail(version, account: viewModel.uiState.account)
            } label: {
                buildVersionRow(version)
            }
            .foregroundStyle(.primary)
        }
        
    }

    private func buildVersionRow(_ version: AppStoreVersionModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(version.versionString ?? "–")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let state = version.appStoreState {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor(state.color))
                            .frame(width: 6, height: 6)
                        Text(state.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func statusColor(_ color: AppStoreStateColor) -> Color {
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
