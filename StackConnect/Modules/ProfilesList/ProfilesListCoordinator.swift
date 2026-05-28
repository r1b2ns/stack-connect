import SwiftUI

enum ProfilesListRoute: Hashable {}

final class ProfilesListCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
