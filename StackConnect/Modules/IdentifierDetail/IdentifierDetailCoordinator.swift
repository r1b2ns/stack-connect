import SwiftUI

enum IdentifierDetailRoute: Hashable {}

final class IdentifierDetailCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
