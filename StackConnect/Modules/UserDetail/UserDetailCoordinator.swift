import SwiftUI

enum UserDetailRoute: Hashable {}

final class UserDetailCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
