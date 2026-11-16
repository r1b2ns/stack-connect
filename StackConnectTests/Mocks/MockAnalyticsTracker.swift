import Foundation
import StackProtocols
@testable import StackConnect

/// In-memory `AnalyticsTracking` for ViewModel and view-helper tests.
/// Mirrors the real gate: `track` only records while enabled.
@MainActor
final class MockAnalyticsTracker: AnalyticsTracking {

    private(set) var isEnabled: Bool
    private(set) var trackedEvents: [AnalyticsEvent] = []
    private(set) var setEnabledCalls: [Bool] = []

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        trackedEvents.append(event)
    }

    func setEnabled(_ enabled: Bool) {
        setEnabledCalls.append(enabled)
        isEnabled = enabled
    }

    // MARK: - Assertion helpers

    /// `button_tap` events recorded for `button`, regardless of screen.
    func taps(of button: AnalyticsButton) -> [AnalyticsEvent] {
        trackedEvents.filter {
            $0.name == AnalyticsEventName.buttonTap
                && $0.parameters[AnalyticsParameterKey.buttonName] == .string(button.rawValue)
        }
    }

    /// `action` events recorded for `action`, regardless of screen.
    func actions(of action: AnalyticsAction) -> [AnalyticsEvent] {
        trackedEvents.filter {
            $0.name == AnalyticsEventName.action
                && $0.parameters[AnalyticsParameterKey.actionName] == .string(action.rawValue)
        }
    }

    /// The `result` values recorded for `action`, in order (nil when an
    /// event was sent without a result).
    func results(of action: AnalyticsAction) -> [AnalyticsResult?] {
        actions(of: action).map { event in
            guard case .string(let raw)? = event.parameters[AnalyticsParameterKey.result] else { return nil }
            return AnalyticsResult(rawValue: raw)
        }
    }
}
