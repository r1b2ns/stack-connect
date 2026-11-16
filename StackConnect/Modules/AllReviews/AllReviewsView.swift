import SwiftUI

// MARK: - Factory

@MainActor
struct AllReviewsViewFactory {
    static func build() -> some View {
        AllReviewsEntry()
    }
}

// MARK: - Entry

private struct AllReviewsEntry: View {
    @StateObject private var viewModel = AllReviewsViewModel()

    var body: some View {
        AllReviewsView(viewModel: viewModel)
    }
}

// MARK: - View

struct AllReviewsView<ViewModel: AllReviewsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Ratings & Reviews"))
            .trackScreen(.allReviews)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    private func buildEmptyState() -> some View {
        ContentUnavailableView {
            Label(String(localized: "No Reviews"), systemImage: "star")
        } description: {
            Text(String(localized: "Reviews will appear after the next sync."))
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.groups) { group in
                Section {
                    ForEach(group.reviews) { item in
                        StackTrackedButton(.review, on: .allReviews) {
                            coordinator.open(item)
                        } label: {
                            HomeReviewRowView(item: item, showsApp: false)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    buildSectionHeader(group)
                } footer: {
                    if group.provider == .googlePlay {
                        Text(String(localized: "Google Play only shares reviews with a comment from the last 7 days."))
                    }
                }
            }
        }
    }

    private func buildSectionHeader(_ group: AllReviewsAppGroup) -> some View {
        HStack(spacing: 8) {
            HomeAppIconView(url: group.iconURL, size: 22)
            Text(group.appName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
            if let platform = group.platform {
                StackPlatformGlyphView(platform: platform)
            }

            Spacer()

            StackTrackedButton(.seeMore, on: .allReviews) {
                coordinator.open(group.target, accountId: group.accountId, account: group.account)
            } label: {
                HStack(spacing: 2) {
                    Text(String(localized: "See more"))
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}
