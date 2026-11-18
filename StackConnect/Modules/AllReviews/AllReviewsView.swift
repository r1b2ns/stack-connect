import SwiftUI

// MARK: - Factory

@MainActor
struct AllReviewsViewFactory {
    /// - Parameter showsFilter: the store / unreplied filter menu; on in the
    ///   split view inbox, off on iPhone.
    static func build(showsFilter: Bool = false) -> some View {
        AllReviewsEntry(showsFilter: showsFilter)
    }
}

// MARK: - Entry

private struct AllReviewsEntry: View {
    let showsFilter: Bool
    @StateObject private var viewModel = AllReviewsViewModel()

    var body: some View {
        AllReviewsView(viewModel: viewModel, showsFilter: showsFilter)
    }
}

// MARK: - View

struct AllReviewsView<ViewModel: AllReviewsViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    var showsFilter = false
    @EnvironmentObject private var coordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .toolbar {
                // Split view inbox: filter by store or by reviews still
                // waiting for a reply.
                if showsFilter && !viewModel.uiState.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        buildFilterMenu()
                    }
                }
            }
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

    private func buildFilterMenu() -> some View {
        Menu {
            Picker(String(localized: "Filter"), selection: Binding(
                get: { viewModel.uiState.filter },
                set: { viewModel.applyFilter($0) }
            )) {
                ForEach(AllReviewsFilter.allCases) { filter in
                    if filter == .unreplied {
                        Text(verbatim: "\(filter.title) (\(viewModel.uiState.unrepliedCount))").tag(filter)
                    } else {
                        Text(filter.title).tag(filter)
                    }
                }
            }
        } label: {
            Label(
                String(localized: "Filter"),
                systemImage: viewModel.uiState.filter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
    }

    private func buildList() -> some View {
        List {
            if viewModel.uiState.visibleGroups.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Reviews"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .listRowBackground(Color.clear)
            }
            ForEach(viewModel.uiState.visibleGroups) { group in
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
