import SwiftUI

enum CreateCertificateRoute: Hashable {}

final class CreateCertificateCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
