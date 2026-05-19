import SwiftUI

// MARK: - Factory

@MainActor
struct BuildSelectionViewFactory {
    static func build(versionId: String, appId: String, account: AccountModel) -> some View {
        BuildSelectionEntry(versionId: versionId, appId: appId, account: account)
    }
}

// MARK: - Entry

private struct BuildSelectionEntry: View {
    let versionId: String
    let appId: String
    let account: AccountModel

    @StateObject private var viewModel: BuildSelectionViewModel

    init(versionId: String, appId: String, account: AccountModel) {
        self.versionId = versionId
        self.appId = appId
        self.account = account
        _viewModel = StateObject(wrappedValue: BuildSelectionViewModel(versionId: versionId, appId: appId, account: account))
    }

    var body: some View {
        BuildSelectionView(viewModel: viewModel)
    }
}

// MARK: - View

struct BuildSelectionView<ViewModel: BuildSelectionViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Select Build"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.loadBuilds() }
            .onChange(of: viewModel.uiState.didSelect) { _, didSelect in
                if didSelect { dismiss() }
            }
    }

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.builds.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No Builds"), systemImage: "hammer")
            } description: {
                Text("Upload a build from Xcode first.")
            }
        } else {
            buildList()
        }
    }

    private func buildList() -> some View {
        List(viewModel.uiState.builds) { build in
            Button {
                Task { await viewModel.selectBuild(build) }
            } label: {
                buildRow(build)
            }
            .disabled(viewModel.uiState.isAttaching)
            .foregroundStyle(.primary)
        }
        
    }

    private func buildRow(_ build: BuildModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(build.displayVersion)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .truncationMode(.middle)

                if let date = build.uploadedDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let state = build.processingState {
                    Text(state)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if build.id == viewModel.uiState.currentBuildId {
                Image(systemName: "checkmark")
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
            }
        }
    }
}
