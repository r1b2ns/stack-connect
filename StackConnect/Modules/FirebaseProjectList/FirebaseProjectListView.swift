import SwiftUI

// MARK: - Factory

@MainActor
struct FirebaseProjectListViewFactory {
    static func build(account: AccountModel) -> some View {
        FirebaseProjectListEntry(account: account)
    }
}

// MARK: - Entry

private struct FirebaseProjectListEntry: View {
    let account: AccountModel

    @StateObject private var viewModel: FirebaseProjectListViewModel

    init(account: AccountModel) {
        self.account = account
        _viewModel = StateObject(wrappedValue: FirebaseProjectListViewModel(account: account))
    }

    var body: some View {
        FirebaseProjectListView(viewModel: viewModel)
    }
}

// MARK: - View

struct FirebaseProjectListView<ViewModel: FirebaseProjectListViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var homeCoordinator: HomeCoordinator

    var body: some View {
        buildContent()
            .navigationTitle(viewModel.uiState.account.name)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search by name or project ID")
            )
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.projects.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.uiState.filteredProjects.isEmpty {
            buildEmptyState()
        } else {
            buildList()
        }
    }

    @ViewBuilder
    private func buildEmptyState() -> some View {
        if !viewModel.uiState.searchQuery.isEmpty {
            ContentUnavailableView.search(text: viewModel.uiState.searchQuery)
        } else if let error = viewModel.uiState.error {
            ContentUnavailableView {
                Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Projects"), systemImage: "flame")
            } description: {
                Text("No Firebase projects found for this account.")
            }
        }
    }

    private func buildList() -> some View {
        List {
            ForEach(viewModel.uiState.filteredProjects) { project in
                Button {
                    homeCoordinator.navigateToFirebaseProjectDetail(
                        project: project,
                        account: viewModel.uiState.account
                    )
                } label: {
                    buildProjectRow(project)
                }
                .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Project Row

    private func buildProjectRow(_ project: FirebaseProjectModel) -> some View {
        HStack(spacing: 12) {
            buildProjectIcon(project)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text(project.projectId)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let location = project.locationId {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption2)
                        Text(location)
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            buildStateBadge(project.state)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func buildProjectIcon(_ project: FirebaseProjectModel) -> some View {
        Image(systemName: "flame.fill")
            .font(.body)
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func buildStateBadge(_ state: String?) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case "ACTIVE":  return (String(localized: "Active"), .green)
            case "DELETED": return (String(localized: "Deleted"), .red)
            default:        return ("–", .gray)
            }
        }()

        return Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
