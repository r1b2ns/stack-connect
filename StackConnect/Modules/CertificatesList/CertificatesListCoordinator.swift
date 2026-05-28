import SwiftUI

enum CertificatesListRoute: Hashable {}

final class CertificatesListCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
