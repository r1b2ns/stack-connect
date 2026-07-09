import SwiftUI

enum AnalyticsReportFilesRoute: Hashable {}

/// Local navigation host for the analytics files screen. It has no in-module
/// routes today; it exists to mirror the module template.
final class AnalyticsReportFilesCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
