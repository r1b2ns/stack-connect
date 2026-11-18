import Foundation
import StackProtocols

/// Bridges deep links that arrive outside the SwiftUI environment (e.g. a local
/// notification tap handled in the AppDelegate) into the view layer. The Home
/// entry observes `pending` and routes it through the coordinator.
///
/// Links opened from outside the app (a notification, a widget, a URL) pass
/// their `source` and are tracked as `app_opened_from` with the route kind —
/// never the URL or its ids. In-app links (e.g. "Re-import File") pass none.
@MainActor
final class DeepLinkRouter: ObservableObject {

    static let shared = DeepLinkRouter()

    @Published var pending: URL?

    private let analytics: AnalyticsTracking

    init(analytics: AnalyticsTracking = AnalyticsService.shared) {
        self.analytics = analytics
    }

    func open(_ url: URL, source: DeepLinkSource? = nil) {
        if let source {
            analytics.track(.appOpened(from: source, destination: AnalyticsDeepLinkDestination(url: url)))
        }
        pending = url
    }
}
