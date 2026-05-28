import SwiftUI

enum DevicesListRoute: Hashable {}

final class DevicesListCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
