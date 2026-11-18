import SwiftUI
import StackProtocols

/// Remembers which error a view already reported, so `error_shown` is sent
/// once per distinct error while the view lives — not on every re-render,
/// List row recycling or return to the screen with the same error.
///
/// Only a hash of the message is kept, in memory; the message is never sent.
struct ErrorShownDeduplicator: Equatable {

    private var lastReportedHash: Int?

    /// `true` the first time `message` is seen (or after another message).
    mutating func shouldReport(_ message: String) -> Bool {
        let hash = message.hashValue
        guard hash != lastReportedHash else { return false }
        lastReportedHash = hash
        return true
    }
}

/// Sends `error_shown` when the modified error view appears, and again only
/// when it starts showing a different error. The screen comes from
/// `\.analyticsScreen` (set by `.trackScreen`), so call sites pass nothing.
struct StackTrackErrorShownModifier: ViewModifier {

    let message: String
    let presentation: AnalyticsErrorPresentation
    let category: AnalyticsErrorCategory?

    @Environment(\.analytics) private var analytics
    @Environment(\.analyticsScreen) private var screen
    @State private var deduplicator = ErrorShownDeduplicator()

    func body(content: Content) -> some View {
        content
            .onAppear { report() }
            .onChange(of: message) { report() }
    }

    private func report() {
        Self.reportIfNeeded(
            message: message,
            presentation: presentation,
            category: category,
            on: screen,
            deduplicator: &deduplicator,
            with: analytics
        )
    }

    /// The side effect, split out so it can be unit tested.
    static func reportIfNeeded(
        message: String,
        presentation: AnalyticsErrorPresentation,
        category: AnalyticsErrorCategory?,
        on screen: AnalyticsScreen?,
        deduplicator: inout ErrorShownDeduplicator,
        with analytics: any AnalyticsTracking
    ) {
        guard deduplicator.shouldReport(message) else { return }
        analytics.track(.errorShown(on: screen, presentation: presentation, category: category))
    }
}

extension View {
    /// Reports this error view as shown (`error_shown`), once per distinct
    /// message. Used by the DS error components.
    func trackErrorShown(
        _ message: String,
        presentation: AnalyticsErrorPresentation,
        category: AnalyticsErrorCategory?
    ) -> some View {
        modifier(StackTrackErrorShownModifier(message: message, presentation: presentation, category: category))
    }
}

/// Tracks a "Share Error" tap on the current tracked screen. A `ShareLink`
/// has no action closure, so the tap is observed alongside it.
struct StackTrackShareErrorTapModifier: ViewModifier {

    @Environment(\.analytics) private var analytics
    @Environment(\.analyticsScreen) private var screen

    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded {
            Self.trackTap(on: screen, with: analytics)
        })
    }

    /// Sends `button_tap share_error` when a tracked screen is known.
    static func trackTap(on screen: AnalyticsScreen?, with analytics: any AnalyticsTracking) {
        guard let screen else { return }
        analytics.track(.buttonTap(.shareError, on: screen))
    }
}
