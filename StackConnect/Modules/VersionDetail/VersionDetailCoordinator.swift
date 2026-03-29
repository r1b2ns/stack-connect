import SwiftUI

enum VersionDetailRoute: Hashable {}

final class VersionDetailCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
