import SwiftUI
import StackProtocols

/// Sends a `button_tap` whenever a `Link` (or any `openURL` call) inside the
/// modified view opens a URL, then lets the system open it as before. Use it on
/// `Link`s, which can't be swapped for `StackTrackedButton` without changing
/// their behaviour. The URL itself is never sent.
struct StackTrackOpenURLModifier: ViewModifier {

    let button: AnalyticsButton
    let screen: AnalyticsScreen

    @Environment(\.analytics) private var analytics

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { _ in
            Self.trackOpen(button, on: screen, with: analytics)
        })
    }

    /// The side effect of opening a URL, split out so it can be unit tested.
    @discardableResult
    static func trackOpen(
        _ button: AnalyticsButton,
        on screen: AnalyticsScreen,
        with analytics: any AnalyticsTracking
    ) -> OpenURLAction.Result {
        analytics.track(.buttonTap(button, on: screen))
        return .systemAction
    }
}

extension View {
    /// Tracks `button` on `screen` each time a link inside this view is opened.
    func trackOpenURL(_ button: AnalyticsButton, on screen: AnalyticsScreen) -> some View {
        modifier(StackTrackOpenURLModifier(button: button, screen: screen))
    }
}
