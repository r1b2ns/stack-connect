import Foundation

@MainActor
protocol UserDetailViewModelProtocol: ObservableObject {
    var uiState: UserDetailUiState { get set }
}

struct UserDetailUiState {
    var user: UserModel
}

@MainActor
final class UserDetailViewModel: UserDetailViewModelProtocol {
    @Published var uiState: UserDetailUiState

    init(user: UserModel) {
        self.uiState = UserDetailUiState(user: user)
    }
}
