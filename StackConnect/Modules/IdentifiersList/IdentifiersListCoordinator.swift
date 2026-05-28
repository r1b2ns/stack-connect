import SwiftUI

enum IdentifiersListRoute: Hashable {}

final class IdentifiersListCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
