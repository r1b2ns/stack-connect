import SwiftUI

enum VersionListRoute: Hashable {}

final class VersionListCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
