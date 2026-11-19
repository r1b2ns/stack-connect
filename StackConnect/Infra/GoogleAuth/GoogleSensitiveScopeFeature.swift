import Foundation

/// A Firebase screen that needs a sensitive Google scope the sign-in doesn't
/// ask for (plan G3, Phase 3): it is requested incrementally the first time
/// a "Sign in with Google" account opens the screen.
///
/// The one place that ties a screen to its scope constant
/// (`GoogleOAuthScope`): screens and checks never spell a scope themselves.
enum GoogleSensitiveScopeFeature: String, CaseIterable, Sendable {
    /// Remote Config accepts only `cloud-platform`.
    case remoteConfig
    /// The Analytics Data API (`analytics.readonly`).
    case analytics

    /// The scope this screen needs.
    var scope: String {
        switch self {
        case .remoteConfig: return GoogleOAuthScope.cloudPlatform
        case .analytics:    return GoogleOAuthScope.analyticsReadOnly
        }
    }

    /// `kind` of the `google_scope_grant*` events.
    var analyticsValue: String {
        switch self {
        case .remoteConfig: return "remote_config"
        case .analytics:    return "analytics"
        }
    }

    var systemImage: String {
        switch self {
        case .remoteConfig: return "slider.horizontal.3"
        case .analytics:    return "chart.xyaxis.line"
        }
    }

    var title: String {
        switch self {
        case .remoteConfig: return String(localized: "Allow Remote Config Access")
        case .analytics:    return String(localized: "Allow Analytics Access")
        }
    }

    /// Why the extra permission is needed.
    var explanation: String {
        switch self {
        case .remoteConfig:
            return String(localized: "To read and publish your Remote Config, Google needs one more permission (Google Cloud access). StackConnect asks for it only now, when you open Remote Config.")
        case .analytics:
            return String(localized: "To show your Google Analytics reports, Google needs one more permission. StackConnect only reads your Analytics data and never changes it.")
        }
    }

    /// Every explanation ends with this: what Google may show on its page.
    static var unverifiedAppNotice: String {
        String(localized: "Google may warn that it hasn't verified StackConnect yet. To continue, tap Advanced, then Go to StackConnect, and keep the permission ticked.",
               comment: "Shown before asking Google for an extra (sensitive) permission. 'Advanced' and 'Go to StackConnect' are the labels of Google's own warning page; keep them close to Google's wording in each language.")
    }
}
