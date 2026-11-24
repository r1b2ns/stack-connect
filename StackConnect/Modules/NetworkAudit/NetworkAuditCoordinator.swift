import SwiftUI

/// Screens of the Audit module pushed on the Home stack (`HomeRoute`).
enum NetworkAuditRoute: Hashable {
    case event(NetworkAuditEventSummary)
    case retention
}

/// Sheets of the Audit module.
enum NetworkAuditSheet: Identifiable, Equatable {
    case batchExport(filtered: [NetworkAuditEventSummary], filterTitle: String)
    case eventExport(NetworkAuditEventSummary)

    var id: String {
        switch self {
        case .batchExport: return "batchExport"
        case .eventExport(let summary): return "eventExport.\(summary.id.uuidString)"
        }
    }
}

/// Module-local navigation state of the Audit screens: the selection that
/// drives the detail column on regular width, and the sheets.
///
/// Pushes (event detail on compact width, retention) go through the
/// `HomeCoordinator` the module is shown in (`navigateToNetworkAudit…`), so
/// they land on the right stack in the tab bar and in the split view.
@MainActor
final class NetworkAuditCoordinator: ObservableObject {

    /// The event shown next to the list on regular width.
    @Published var selection: NetworkAuditEventSummary?
    @Published var sheet: NetworkAuditSheet?

    func select(_ summary: NetworkAuditEventSummary) {
        selection = summary
    }

    func presentBatchExport(filtered: [NetworkAuditEventSummary], filterTitle: String) {
        sheet = .batchExport(filtered: filtered, filterTitle: filterTitle)
    }

    func presentEventExport(_ summary: NetworkAuditEventSummary) {
        sheet = .eventExport(summary)
    }

    func dismissSheet() {
        sheet = nil
    }
}
