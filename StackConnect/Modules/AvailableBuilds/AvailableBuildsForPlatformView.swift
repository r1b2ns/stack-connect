import SwiftUI

// MARK: - Factory

@MainActor
struct AvailableBuildsForPlatformViewFactory {
    static func build(
        appId: String,
        platform: String,
        account: AccountModel,
        assignedBuildIds: Set<String>,
        isAdding: Bool,
        onSelect: @escaping (BuildModel) -> Void
    ) -> some View {
        AvailableBuildsForPlatformEntryView(
            appId: appId,
            platform: platform,
            account: account,
            assignedBuildIds: assignedBuildIds,
            isAdding: isAdding,
            onSelect: onSelect
        )
    }
}

// MARK: - Entry

private struct AvailableBuildsForPlatformEntryView: View {
    let appId: String
    let platform: String
    let account: AccountModel
    let assignedBuildIds: Set<String>
    let isAdding: Bool
    let onSelect: (BuildModel) -> Void

    @StateObject private var viewModel: AvailableBuildsForPlatformViewModel

    init(
        appId: String,
        platform: String,
        account: AccountModel,
        assignedBuildIds: Set<String>,
        isAdding: Bool,
        onSelect: @escaping (BuildModel) -> Void
    ) {
        self.appId = appId
        self.platform = platform
        self.account = account
        self.assignedBuildIds = assignedBuildIds
        self.isAdding = isAdding
        self.onSelect = onSelect
        _viewModel = StateObject(wrappedValue: AvailableBuildsForPlatformViewModel(
            appId: appId,
            platform: platform,
            account: account,
            assignedBuildIds: assignedBuildIds
        ))
    }

    var body: some View {
        AvailableBuildsForPlatformView(viewModel: viewModel, isAdding: isAdding, onSelect: onSelect)
    }
}

// MARK: - View

struct AvailableBuildsForPlatformView<ViewModel: AvailableBuildsForPlatformViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    let isAdding: Bool
    let onSelect: (BuildModel) -> Void

    var body: some View {
        buildContent()
            .navigationTitle(BuildPlatform.label(for: viewModel.uiState.platform))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.uiState.builds.isEmpty {
                    await viewModel.load()
                }
            }
            .refreshable { await viewModel.load() }
            .disabled(isAdding)
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.builds.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.builds.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Builds"), systemImage: "hammer")
            } description: {
                Text("No builds are available to add.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            Section {
                ForEach(viewModel.uiState.builds) { build in
                    Button { onSelect(build) } label: {
                        buildRow(build)
                    }
                    .onAppear { handleAppear(build) }
                }

                if viewModel.uiState.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            } header: {
                Label(
                    BuildPlatform.label(for: viewModel.uiState.platform),
                    systemImage: BuildPlatform.icon(for: viewModel.uiState.platform)
                )
            }
        }
    }

    private func buildRow(_ build: BuildModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(build.displayVersion)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let date = build.uploadedDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(String(localized: "Ready"))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func handleAppear(_ build: BuildModel) {
        guard let last = viewModel.uiState.builds.last else { return }
        if build.id == last.id {
            Task { await viewModel.loadMore() }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
