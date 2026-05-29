import Foundation

/// Bridges deep links that arrive outside the SwiftUI environment (e.g. a local
/// notification tap handled in the AppDelegate) into the view layer. The Home
/// entry observes `pending` and routes it through the coordinator.
@MainActor
final class DeepLinkRouter: ObservableObject {

    static let shared = DeepLinkRouter()

    @Published var pending: URL?

    private init() {}

    func open(_ url: URL) {
        pending = url
    }
}
