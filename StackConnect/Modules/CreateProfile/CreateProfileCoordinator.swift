import SwiftUI

enum CreateProfileRoute: Hashable {}

final class CreateProfileCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
