import Foundation
import StackProtocols
@testable import StackConnect

/// In-memory `AnalyticsTracking` for ViewModel and view-helper tests.
/// Mirrors the real gate: `track` and `setUserProperties` only record while enabled.
@MainActor
final class MockAnalyticsTracker: AnalyticsTracking, AnalyticsUserPropertySetting, NonFatalErrorRecording {

    private(set) var isEnabled: Bool
    private(set) var trackedEvents: [AnalyticsEvent] = []
    private(set) var setEnabledCalls: [Bool] = []
    /// Every `setUserProperties` call recorded while enabled, in order.
    private(set) var userPropertyUpdates: [[AnalyticsUserProperty: String]] = []

    /// Every `recordNonFatal` call recorded while enabled, in order.
    private(set) var nonFatals: [(error: Error, category: AnalyticsErrorCategory)] = []

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        trackedEvents.append(event)
    }

    func setUserProperties(_ properties: [AnalyticsUserProperty: String]) {
        guard isEnabled else { return }
        userPropertyUpdates.append(properties)
    }

    /// Mirrors `AnalyticsService`: only while enabled, and only categories
    /// worth a non-fatal (`server` / `unknown`).
    func recordNonFatal(_ error: Error, category: AnalyticsErrorCategory) {
        guard isEnabled, category.isReportableAsNonFatal else { return }
        nonFatals.append((error, category))
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

    /// `error_shown` events, in order.
    var errorShownEvents: [AnalyticsEvent] {
        trackedEvents.filter { $0.name == AnalyticsEventName.errorShown }
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
