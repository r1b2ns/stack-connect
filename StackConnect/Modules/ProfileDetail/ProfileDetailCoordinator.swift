import SwiftUI

enum ProfileDetailRoute: Hashable {}

final class ProfileDetailCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
