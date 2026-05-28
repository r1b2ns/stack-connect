import SwiftUI

enum AccountManagementRoute: Hashable {}

final class AccountManagementCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
