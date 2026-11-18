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
    /// `true`: `screen` is only the fallback for `\.analyticsScreen`.
    private let prefersEnvironmentScreen: Bool
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: Label

    @Environment(\.analytics) private var analytics
    @Environment(\.analyticsScreen) private var environmentScreen

    init(
        _ button: AnalyticsButton,
        on screen: AnalyticsScreen,
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.init(button, screen: screen, prefersEnvironmentScreen: false, role: role, action: action, label: label)
    }

    /// For shared components shown on several screens (Home widgets, which
    /// also fill the split view release queues): the tap is reported on the
    /// tracked screen around the button (`\.analyticsScreen`, set by
    /// `.trackScreen`), or on `fallback` outside any tracked screen.
    init(
        _ button: AnalyticsButton,
        onCurrentScreenOr fallback: AnalyticsScreen,
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.init(button, screen: fallback, prefersEnvironmentScreen: true, role: role, action: action, label: label)
    }

    private init(
        _ button: AnalyticsButton,
        screen: AnalyticsScreen,
        prefersEnvironmentScreen: Bool,
        role: ButtonRole?,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.button = button
        self.screen = screen
        self.prefersEnvironmentScreen = prefersEnvironmentScreen
        self.role = role
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(role: role) {
            let screen = prefersEnvironmentScreen
                ? Self.resolvedScreen(environment: environmentScreen, fallback: screen)
                : screen
            Self.performTap(button, on: screen, with: analytics, action: action)
        } label: {
            label
        }
    }

    /// The screen a `onCurrentScreenOr:` button reports on. Split out so it
    /// can be unit tested.
    static func resolvedScreen(environment: AnalyticsScreen?, fallback: AnalyticsScreen) -> AnalyticsScreen {
        environment ?? fallback
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
