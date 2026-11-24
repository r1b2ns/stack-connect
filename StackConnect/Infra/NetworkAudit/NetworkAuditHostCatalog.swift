import Foundation

/// Who owns each host the app talks to, and why it talks to it. Feeds the
/// category of every event and the Destinations list.
///
/// Unknown hosts are never hidden: they fall in `.other` with a generic purpose.
enum NetworkAuditHostCatalog {

    struct Entry: Equatable, Sendable {
        let category: NetworkAuditCategory
        let purpose: String
    }

    static func entry(host: String, path: String = "") -> Entry {
        let host = host.lowercased()

        switch host {
        case "api.appstoreconnect.apple.com":
            return Entry(category: .apple, purpose: String(localized: "App Store Connect API: apps, versions, builds, TestFlight, users and reviews.", comment: "Network audit: purpose of api.appstoreconnect.apple.com."))
        case "appstoreconnect.apple.com", "idmsa.apple.com", "gsa.apple.com":
            return Entry(category: .apple, purpose: String(localized: "Apple ID session for features the public API doesn't cover.", comment: "Network audit: purpose of the Apple ID web session hosts."))
        case "itunes.apple.com":
            return Entry(category: .apple, purpose: String(localized: "Public App Store lookup: ratings summary of your apps.", comment: "Network audit: purpose of itunes.apple.com."))
        case "androidpublisher.googleapis.com":
            return Entry(category: .google, purpose: String(localized: "Google Play Developer API: apps, tracks, listings and reviews.", comment: "Network audit: purpose of androidpublisher.googleapis.com."))
        case "firebase.googleapis.com":
            return Entry(category: .google, purpose: String(localized: "Firebase Management: projects and apps of your accounts.", comment: "Network audit: purpose of firebase.googleapis.com."))
        case "oauth2.googleapis.com", "accounts.google.com", "www.googleapis.com", "openidconnect.googleapis.com":
            return Entry(category: .google, purpose: String(localized: "Google sign-in and service account token renewal.", comment: "Network audit: purpose of the Google OAuth hosts."))
        case "firebaseremoteconfig.googleapis.com":
            // The SDK fetch of the app's own flags vs. the Remote Config
            // screen of the user's Firebase projects (REST `…/remoteConfig`).
            if path.contains("namespaces/firebase:fetch") {
                return telemetryRemoteConfig
            }
            return Entry(category: .google, purpose: String(localized: "Remote Config of your Firebase projects.", comment: "Network audit: purpose of firebaseremoteconfig.googleapis.com for the user's projects."))
        case "firebaselogging-pa.googleapis.com", "firebaselogging.googleapis.com":
            return Entry(category: .telemetry, purpose: String(localized: "Firebase SDK diagnostics: delivery of analytics and crash data.", comment: "Network audit: purpose of the Firebase logging hosts."))
        case "firebase-settings.crashlytics.com", "crashlyticsreports-pa.googleapis.com", "reports.crashlytics.com", "update.crashlytics.com":
            return Entry(category: .telemetry, purpose: String(localized: "Crashlytics: settings and crash reports of the app.", comment: "Network audit: purpose of the Crashlytics hosts."))
        case "firebaseinstallations.googleapis.com":
            return Entry(category: .telemetry, purpose: String(localized: "Firebase installation ID used by analytics and remote configuration.", comment: "Network audit: purpose of firebaseinstallations.googleapis.com."))
        case "firebaseremoteconfigrealtime.googleapis.com":
            return telemetryRemoteConfig
        default:
            break
        }

        // Google Analytics for Firebase: `app-measurement.com` and
        // `app-analytics-services.com`, with their regional subdomains.
        if Self.matches(host, domain: "app-measurement.com") || Self.matches(host, domain: "app-analytics-services.com") {
            return analytics
        }

        if host.hasSuffix(".mzstatic.com") {
            return Entry(category: .apple, purpose: String(localized: "App icons and screenshots served by Apple.", comment: "Network audit: purpose of the mzstatic.com image hosts."))
        }
        if host.hasSuffix(".googleusercontent.com") || host.hasSuffix(".ggpht.com") {
            return Entry(category: .google, purpose: String(localized: "App icons and images served by Google.", comment: "Network audit: purpose of Google image hosts."))
        }
        if host.hasSuffix(".apple.com") {
            return Entry(category: .apple, purpose: String(localized: "An Apple service.", comment: "Network audit: purpose of an unknown apple.com host."))
        }
        if host.hasSuffix(".googleapis.com") || host.hasSuffix(".google.com") {
            return Entry(category: .google, purpose: String(localized: "A Google service.", comment: "Network audit: purpose of an unknown Google host."))
        }
        return Entry(category: .other, purpose: String(localized: "A destination outside the services above.", comment: "Network audit: purpose of an unknown host."))
    }

    private static func matches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static var analytics: Entry {
        Entry(category: .telemetry, purpose: String(localized: "StackConnect analytics: screens visited and buttons tapped. Turn it off in Settings › Privacy.", comment: "Network audit: purpose of the analytics hosts."))
    }

    private static var telemetryRemoteConfig: Entry {
        Entry(category: .telemetry, purpose: String(localized: "Remote configuration: turns app features on and off.", comment: "Network audit: purpose of the app's own Remote Config fetch."))
    }
}
