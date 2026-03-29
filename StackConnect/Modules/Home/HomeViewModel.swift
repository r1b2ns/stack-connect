import Foundation

// MARK: - Protocol

protocol HomeViewModelProtocol: ObservableObject {
    var uiState: HomeUiState { get set }
}

// MARK: - UiState

struct HomeUiState {
    var providers: [ProviderType] = ProviderType.allCases
}

// MARK: - Implementation

final class HomeViewModel: HomeViewModelProtocol {
    @Published var uiState = HomeUiState()
}
