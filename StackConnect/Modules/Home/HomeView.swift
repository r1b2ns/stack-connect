import SwiftUI

// MARK: - Factory

struct HomeViewFactory {
    static func build() -> some View {
        HomeEntry()
    }
}

// MARK: - Entry

private struct HomeEntry: View {
    @StateObject private var coordinator = HomeCoordinator()
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        HomeView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

// MARK: - View

struct HomeView<ViewModel: HomeViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel
    @EnvironmentObject private var coordinator: HomeCoordinator

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            buildContent()
                .navigationTitle("StackConnect")
                .navigationDestinations()
        }
    }

    // MARK: - Content

    private func buildContent() -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.uiState.providers, id: \.self) { provider in
                    ProviderCardView(provider: provider)
                        .onTapGesture {
                            coordinator.navigateToAccountsList(provider)
                        }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Navigation Destinations

private extension View {
    @ViewBuilder
    func navigationDestinations() -> some View {
        self.navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .accountsList(let providerType):
                AccountsListViewFactory.build(providerType: providerType)
            }
        }
    }
}
