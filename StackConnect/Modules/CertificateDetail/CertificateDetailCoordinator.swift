import SwiftUI

enum CertificateDetailRoute: Hashable {}

final class CertificateDetailCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
