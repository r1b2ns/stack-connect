import SwiftUI

enum ImportDevicesRoute: Hashable {}

final class ImportDevicesCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
