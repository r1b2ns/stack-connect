import SwiftUI
import StackProtocols

/// Design System drop-in replacement for `Button` that sends a `button_tap`
/// event before running its action.
///
/// Use it for taps that only navigate (coordinator calls, sheets, links).
/// Taps that trigger work should track from the ViewModel instead, together
/// with the outcome, so the events are covered by ViewModel tests.
///
/// ```swift
/// StackTrackedButton(.addAccount, on: .home) {
///     coordinator.navigateToAddAccount()
/// } label: {
///     Label(String(localized: "Add Account"), systemImage: "plus")
/// }
/// ```
struct StackTrackedButton<Label: View>: View {

    private let button: AnalyticsButton
    private let screen: AnalyticsScreen
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: Label

    @Environment(\.analytics) private var analytics

    init(
        _ button: AnalyticsButton,
        on screen: AnalyticsScreen,
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.button = button
        self.screen = screen
        self.role = role
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(role: role) {
            Self.performTap(button, on: screen, with: analytics, action: action)
        } label: {
            label
        }
    }

    /// Tracks the tap, then runs `action`. Split out so it can be unit tested.
    static func performTap(
        _ button: AnalyticsButton,
        on screen: AnalyticsScreen,
        with analytics: any AnalyticsTracking,
        action: () -> Void
    ) {
        analytics.track(.buttonTap(button, on: screen))
        action()
    }
}

extension StackTrackedButton where Label == Text {
    /// Convenience for a plain text label.
    init(
        _ title: String,
        button: AnalyticsButton,
        on screen: AnalyticsScreen,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(button, on: screen, role: role, action: action) {
            Text(title)
        }
    }
}
