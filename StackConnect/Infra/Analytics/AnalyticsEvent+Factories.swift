import Foundation
import StackProtocols

/// Event and parameter names used across the app. Centralised so providers,
/// tests and dashboards agree on one spelling.
enum AnalyticsEventName {
    static let screenView = "screen_view"
    static let buttonTap = "button_tap"
    static let action = "action"
    static let analyticsDisabled = "analytics_disabled"
    static let analyticsEnabled = "analytics_enabled"
}

enum AnalyticsParameterKey {
    static let screenName = "screen_name"
    static let buttonName = "button_name"
    static let actionName = "action_name"
    static let result = "result"

    // Optional, PII-free extra parameters shared by `action` events.
    static let count = "count"
    static let failedCount = "failed_count"
    static let enabled = "enabled"
    static let kind = "kind"
    static let hasExpiration = "has_expiration"
    static let scoped = "scoped"
    static let hasAccountHolder = "has_account_holder"
    /// A star rating (1–5) used as a filter — never review content.
    static let rating = "rating"
    /// Number of Remote Config conditions in a published template.
    static let conditionCount = "condition_count"

    /// Shape of an account export (never its content): whether it expires and
    /// whether it is restricted to a subset of apps.
    static func exportParameters(expirationDate: Date?, appsBundles: [String]?) -> [String: AnalyticsValue] {
        [
            hasExpiration: .bool(expirationDate != nil),
            scoped: .bool(!(appsBundles ?? []).isEmpty)
        ]
    }

    // Standard parameters attached by `AnalyticsService` to every event.
    static let appVersion = "app_version"
    static let buildNumber = "build_number"
    static let platform = "platform"
    static let osVersion = "os_version"
}

/// Typed factories so call sites never build raw event strings.
extension AnalyticsEvent {

    /// A screen became visible.
    static func screenView(_ screen: AnalyticsScreen) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.screenView,
            parameters: [AnalyticsParameterKey.screenName: .string(screen.rawValue)]
        )
    }

    /// The user tapped `button` on `screen`.
    static func buttonTap(_ button: AnalyticsButton, on screen: AnalyticsScreen) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.buttonTap,
            parameters: [
                AnalyticsParameterKey.buttonName: .string(button.rawValue),
                AnalyticsParameterKey.screenName: .string(screen.rawValue)
            ]
        )
    }

    /// Meaningful work happened on `screen`, optionally with its outcome.
    /// `parameters` must only carry typed, PII-free values (counts, flags,
    /// enum raw values) — the reserved keys above always win.
    static func action(
        _ action: AnalyticsAction,
        on screen: AnalyticsScreen,
        result: AnalyticsResult? = nil,
        parameters: [String: AnalyticsValue] = [:]
    ) -> AnalyticsEvent {
        var merged = parameters
        merged[AnalyticsParameterKey.actionName] = .string(action.rawValue)
        merged[AnalyticsParameterKey.screenName] = .string(screen.rawValue)
        if let result {
            merged[AnalyticsParameterKey.result] = .string(result.rawValue)
        }
        return AnalyticsEvent(name: AnalyticsEventName.action, parameters: merged)
    }

    /// The opt-out "last event", sent right before sending stops.
    static let analyticsDisabled = AnalyticsEvent(name: AnalyticsEventName.analyticsDisabled)

    /// Sent right after the user turns analytics back on.
    static let analyticsEnabled = AnalyticsEvent(name: AnalyticsEventName.analyticsEnabled)
}
