import SwiftUI

enum AnalyticsReportsRoute: Hashable {}

/// Local navigation host for the predefined-report menu. Cross-module navigation
/// (to the report detail screen) always goes through `HomeCoordinator`; this
/// coordinator exists to mirror the module template and own any future in-module
/// routes.
final class AnalyticsReportsCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
