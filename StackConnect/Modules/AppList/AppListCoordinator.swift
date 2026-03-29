import SwiftUI

enum AppListRoute: Hashable {}

final class AppListCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
