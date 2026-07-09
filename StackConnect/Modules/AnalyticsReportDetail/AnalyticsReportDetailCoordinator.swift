import SwiftUI

enum AnalyticsReportDetailRoute: Hashable {}

/// Local navigation host for the report detail screen. It has no in-module
/// routes today; it exists to mirror the module template.
final class AnalyticsReportDetailCoordinator: MainCoordinatorProtocol {
    @Published var path = NavigationPath()
}
