import SwiftUI

enum AppDetailRoute: Hashable {}

final class AppDetailCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
