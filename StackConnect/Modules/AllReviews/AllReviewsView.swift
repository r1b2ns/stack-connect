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
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.items.isEmpty {
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
            Section {
                ForEach(viewModel.uiState.items) { item in
                    Button {
                        coordinator.navigateToReviewDetail(
                            review: item.review,
                            appName: item.app.name,
                            account: HomeWidgetDataLoader.account(for: item.app, in: viewModel.uiState.accountsMap)
                        )
                    } label: {
                        HomeReviewRowView(item: item)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Reviews (\(viewModel.uiState.items.count))")
            }
        }
    }
}
