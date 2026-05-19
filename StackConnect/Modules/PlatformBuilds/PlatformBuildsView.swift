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
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

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
            .toast(message: $viewModel.uiState.toastMessage)
            .alert(
                String(localized: "Expire Build"),
                isPresented: Binding(
                    get: { viewModel.uiState.confirmExpireBuild != nil },
                    set: { if !$0 { viewModel.uiState.confirmExpireBuild = nil } }
                )
            ) {
                Button(String(localized: "Expire"), role: .destructive) {
                    if let build = viewModel.uiState.confirmExpireBuild {
                        Task { await viewModel.expireBuild(build) }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                if let build = viewModel.uiState.confirmExpireBuild {
                    Text("Expire build \(build.displayVersion)? Testers will no longer be able to install it. This cannot be undone via the API.")
                }
            }
            .alert(
                String(localized: "Expire Failed"),
                isPresented: Binding(
                    get: { viewModel.uiState.expireError != nil },
                    set: { if !$0 { viewModel.uiState.expireError = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                if let message = viewModel.uiState.expireError {
                    Text(message)
                }
            }
            .overlay {
                if viewModel.uiState.isExpiringBuild {
                    ZStack {
                        Color.black.opacity(0.1)
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    .ignoresSafeArea()
                }
            }
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
                    Button {
                        homeCoordinator.navigateToBuildDetail(
                            build: build,
                            appId: viewModel.uiState.appId,
                            account: viewModel.uiState.account
                        )
                    } label: {
                        buildBuildRow(build)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        if !build.isExpired && viewModel.uiState.account.canDelete(.testFlight) {
                            Button {
                                viewModel.uiState.confirmExpireBuild = build
                            } label: {
                                Label(String(localized: "Expire"), systemImage: "clock.badge.xmark")
                            }
                            .tint(.orange)
                        }
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

    private func buildBuildRow(_ build: BuildModel) -> some View {
        let icon = build.isExpired ? "clock.badge.xmark" : buildStateIcon(build.processingState)
        let label = build.isExpired ? String(localized: "Expired") : buildStateLabel(build.processingState)
        let color: Color = build.isExpired ? .gray : buildStateColor(build.processingState)

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(build.displayVersion)
                    .font(.body)
                    .fontWeight(.medium)
                    .truncationMode(.middle)

                if let date = build.uploadedDate {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.12))
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
