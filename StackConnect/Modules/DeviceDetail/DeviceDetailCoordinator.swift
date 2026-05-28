import SwiftUI

enum DeviceDetailRoute: Hashable {}

final class DeviceDetailCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
