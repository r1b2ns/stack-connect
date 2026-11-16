import SwiftUI
import StackProtocols

/// Tracks a `screen_view` every time the modified view appears. Going back to a
/// screen counts again, which matches the usual `screen_view` semantics.
struct StackTrackScreenModifier: ViewModifier {

    let screen: AnalyticsScreen

    @Environment(\.analytics) private var analytics

    func body(content: Content) -> some View {
        content.onAppear {
            Self.trackAppear(of: screen, with: analytics)
        }
    }

    /// The side effect of `onAppear`, split out so it can be unit tested.
    static func trackAppear(of screen: AnalyticsScreen, with analytics: any AnalyticsTracking) {
        analytics.track(.screenView(screen))
    }
}

extension View {
    /// Sends `screen_view` for `screen` whenever this view appears.
    /// Apply it once, to a module's main view body.
    func trackScreen(_ screen: AnalyticsScreen) -> some View {
        modifier(StackTrackScreenModifier(screen: screen))
    }
}
