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
    /// An error became visible (full screen or inline). A distinct concept
    /// from `action`: it reports what the user *saw*, whatever caused it.
    static let errorShown = "error_shown"
    /// The app was opened (or brought to a screen) from outside: a
    /// notification, a widget or a `stackconnect://` URL.
    static let appOpenedFrom = "app_opened_from"
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
    /// A tip's App Store product ID (a fixed catalog value, never user data).
    static let productId = "product_id"
    /// Why a failure happened, as an `AnalyticsErrorCategory` raw value — the
    /// only error information ever sent (never the error's text).
    static let errorCategory = "error_category"
    /// How an error was shown: `AnalyticsErrorPresentation` raw value.
    static let presentation = "presentation"
    /// What started a sync: `SyncTrigger` raw value.
    static let trigger = "trigger"
    /// How long work took, bucketed: `AnalyticsDurationBucket` raw value.
    static let durationBucket = "duration_bucket"
    /// A Google Play track, by kind only: `AnalyticsTrackKind` raw value
    /// (custom track names are user-chosen, so never sent).
    static let track = "track"
    /// Whether a Google Play write was sent for review right away.
    static let sendForReview = "send_for_review"
    /// Where an app open came from: `DeepLinkSource` raw value. Also where a
    /// split view navigation / menu command came from:
    /// `AnalyticsNavigationOrigin` raw value (`navigate`, `find`, `refresh`).
    static let source = "source"
    /// The deep-link route kind opened: `AnalyticsDeepLinkDestination` raw
    /// value. Also the split view sidebar item kind opened by `navigate`:
    /// `AnalyticsSidebarDestination` raw value.
    static let destination = "destination"
    /// Number of results of a search, bucketed: `AnalyticsCountBucket` raw value.
    static let resultCountBucket = "result_count_bucket"
    /// How a new account authenticates: `AccountAuthMethod.analyticsValue`.
    /// Sent by `create_account` for Google sign-in (`google_sign_in`, with
    /// `count` accounts added); absent for the key-file path.
    static let authMethod = "auth_method"
    /// How many requested Google scopes the user left unticked on the consent
    /// page (never which ones by name beyond this count).
    static let missingScopeCount = "missing_scope_count"

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
    ///
    /// `screen` is `nil` only for work no screen owns (a background sync, the
    /// launch notification prompt, the app-wide offline banner): the event is
    /// then sent without `screen_name`.
    static func action(
        _ action: AnalyticsAction,
        on screen: AnalyticsScreen?,
        result: AnalyticsResult? = nil,
        parameters: [String: AnalyticsValue] = [:]
    ) -> AnalyticsEvent {
        var merged = parameters
        merged[AnalyticsParameterKey.actionName] = .string(action.rawValue)
        merged[AnalyticsParameterKey.screenName] = nil
        if let screen {
            merged[AnalyticsParameterKey.screenName] = .string(screen.rawValue)
        }
        if let result {
            merged[AnalyticsParameterKey.result] = .string(result.rawValue)
        }
        return AnalyticsEvent(name: AnalyticsEventName.action, parameters: merged)
    }

    /// An error became visible on `screen` (`nil` when no tracked screen is
    /// above it). Only the category is sent, never the message.
    static func errorShown(
        on screen: AnalyticsScreen?,
        presentation: AnalyticsErrorPresentation,
        category: AnalyticsErrorCategory?
    ) -> AnalyticsEvent {
        var parameters: [String: AnalyticsValue] = [
            AnalyticsParameterKey.presentation: .string(presentation.rawValue)
        ]
        if let screen {
            parameters[AnalyticsParameterKey.screenName] = .string(screen.rawValue)
        }
        if let category {
            parameters[AnalyticsParameterKey.errorCategory] = .string(category.rawValue)
        }
        return AnalyticsEvent(name: AnalyticsEventName.errorShown, parameters: parameters)
    }

    /// The app opened `destination` from `source`. Never the URL or its ids.
    static func appOpened(from source: DeepLinkSource, destination: AnalyticsDeepLinkDestination) -> AnalyticsEvent {
        AnalyticsEvent(
            name: AnalyticsEventName.appOpenedFrom,
            parameters: [
                AnalyticsParameterKey.source: .string(source.rawValue),
                AnalyticsParameterKey.destination: .string(destination.rawValue)
            ]
        )
    }

    /// A split view sidebar destination opened from `origin` (no screen: the
    /// split view root is not one). Only the item kind, never an account.
    static func navigate(to item: RootSidebarItem, from origin: AnalyticsNavigationOrigin) -> AnalyticsEvent {
        .action(
            .navigate,
            on: nil,
            parameters: [
                AnalyticsParameterKey.destination: .string(AnalyticsSidebarDestination(item).rawValue),
                AnalyticsParameterKey.source: .string(origin.rawValue)
            ]
        )
    }

    /// The opt-out "last event", sent right before sending stops.
    static let analyticsDisabled = AnalyticsEvent(name: AnalyticsEventName.analyticsDisabled)

    /// Sent right after the user turns analytics back on.
    static let analyticsEnabled = AnalyticsEvent(name: AnalyticsEventName.analyticsEnabled)
}
