import SwiftUI

enum HomeRoute: Hashable {
    case accountsList(ProviderType)
}

final class HomeCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()

    func navigateToAccountsList(_ providerType: ProviderType) {
        path.append(HomeRoute.accountsList(providerType))
    }
}
