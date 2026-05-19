import SwiftUI

// MARK: - Factory

@MainActor
struct PlatformBuildsViewFactory {
    static func build(appId: String, platform: String, account: AccountModel) -> some View {
        PlatformBuildsEntryView(appId: appId, platform: platform, account: account)
    }
}

// MARK: - Entry

private struct PlatformBuildsEntryView: View {
    let appId: String
    let platform: String
    let account: AccountModel

    @StateObject private var viewModel: PlatformBuildsViewModel

    init(appId: String, platform: String, account: AccountModel) {
        self.appId = appId
        self.platform = platform
        self.account = account
        _viewModel = StateObject(wrappedValue: PlatformBuildsViewModel(appId: appId, platform: platform, account: account))
    }

    var body: some View {
        PlatformBuildsView(viewModel: viewModel)
    }
}

// MARK: - View

struct PlatformBuildsView<ViewModel: PlatformBuildsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

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
                Text("There are no builds for this platform yet.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            Section {
                ForEach(viewModel.uiState.builds) { build in
                    buildBuildRow(build)
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

    private func buildBuildRow(_ build: BuildModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: buildStateIcon(build.processingState))
                .font(.body)
                .foregroundStyle(buildStateColor(build.processingState))

            VStack(alignment: .leading, spacing: 2) {
                Text(build.displayVersion)
                    .font(.body)
                    .fontWeight(.medium)

                if let date = build.uploadedDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(buildStateLabel(build.processingState))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(buildStateColor(build.processingState))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(buildStateColor(build.processingState).opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Helpers

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

    private func buildStateIcon(_ state: String?) -> String {
        switch state {
        case "VALID":      return "checkmark.circle.fill"
        case "PROCESSING": return "arrow.triangle.2.circlepath"
        case "FAILED":     return "xmark.circle.fill"
        case "INVALID":    return "exclamationmark.circle.fill"
        default:           return "circle"
        }
    }

    private func buildStateColor(_ state: String?) -> Color {
        switch state {
        case "VALID":      return .green
        case "PROCESSING": return .orange
        case "FAILED":     return .red
        case "INVALID":    return .red
        default:           return .gray
        }
    }

    private func buildStateLabel(_ state: String?) -> String {
        switch state {
        case "VALID":      return String(localized: "Ready")
        case "PROCESSING": return String(localized: "Processing")
        case "FAILED":     return String(localized: "Failed")
        case "INVALID":    return String(localized: "Invalid")
        default:           return "–"
        }
    }
}
