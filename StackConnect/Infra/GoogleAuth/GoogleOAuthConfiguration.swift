import Foundation

// MARK: - Configuration

/// The app's iOS OAuth client for "Sign in with Google" (plan G1, G8).
///
/// iOS clients have no secret: PKCE proves the caller. The client ID is public
/// and comes from the build settings: `GOOGLE_OAUTH_CLIENT_ID` in
/// `Configs/Debug.xcconfig` / `Configs/Release.xcconfig`, exposed to the app as
/// the Info.plist key `GoogleOAuthClientID` (`project.yml`). Swapping to the
/// production Cloud project is a change of that one value.
///
/// The redirect is the reversed client ID scheme handled by
/// `ASWebAuthenticationSession`, so no Info.plist URL type is needed.
struct GoogleOAuthConfiguration: Equatable, Sendable {

    static let infoPlistKey = "GoogleOAuthClientID"
    static let clientIdSuffix = ".apps.googleusercontent.com"
    static let reversedClientIdPrefix = "com.googleusercontent.apps."

    let clientId: String

    /// `nil` unless `clientId` looks like an iOS OAuth client ID.
    init?(clientId: String) {
        let trimmed = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(Self.clientIdSuffix),
              trimmed.count > Self.clientIdSuffix.count else { return nil }
        self.clientId = trimmed
    }

    /// The configuration bundled with the app, or `nil` when the build has no
    /// (valid) client ID.
    static func fromBundle(_ bundle: Bundle = .main) -> GoogleOAuthConfiguration? {
        guard let value = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String else { return nil }
        return GoogleOAuthConfiguration(clientId: value)
    }

    /// The reversed client ID, e.g. `com.googleusercontent.apps.1234-abc`.
    var redirectScheme: String {
        Self.reversedClientIdPrefix + String(clientId.dropLast(Self.clientIdSuffix.count))
    }

    var redirectURI: String {
        "\(redirectScheme):/oauth2redirect"
    }
}

// MARK: - Endpoints

/// Every Google URL the sign-in flow and the account picker call.
enum GoogleOAuthEndpoint {
    // Constant, well-formed URLs: the force unwraps cannot fail.
    static let authorization = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let token = URL(string: "https://oauth2.googleapis.com/token")!
    static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// Firebase Management: the projects the user can see.
    static let firebaseProjects = URL(string: "https://firebase.googleapis.com/v1beta1/projects")!
    /// Play Developer Reporting: the Play apps the user can see.
    static let playApps = URL(string: "https://playdeveloperreporting.googleapis.com/v1beta1/apps:search")!
}

// MARK: - Scopes

/// OAuth scopes the app requests, and what each one unlocks (plan G3).
enum GoogleOAuthScope {

    static let prefix = "https://www.googleapis.com/auth/"

    // Identity (non-sensitive): the `sub` and `email` claims of the ID token,
    // which identify one Google login on the device.
    static let openID = "openid"
    static let email = prefix + "userinfo.email"

    // Base API scopes (non-sensitive), requested at sign-in.
    static let firebase = prefix + "firebase"
    static let firebaseMessaging = prefix + "firebase.messaging"
    static let androidPublisher = prefix + "androidpublisher"
    static let playDeveloperReporting = prefix + "playdeveloperreporting"

    // Sensitive scopes, requested incrementally on first use (Phase 3).
    /// Remote Config accepts only this one.
    static let cloudPlatform = prefix + "cloud-platform"
    static let analyticsReadOnly = prefix + "analytics.readonly"

    static let identity = [openID, email]

    /// What "Sign in with Google" asks for: identity plus every non-sensitive
    /// API scope, so one login can add Play and Firebase accounts (plan G5).
    static let signIn = identity + [firebase, firebaseMessaging, androidPublisher, playDeveloperReporting]

    /// The `scope` field of a token response (space-separated).
    static func parse(_ value: String?) -> Set<String> {
        guard let value else { return [] }
        return Set(value.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// The scopes of `requested` Google did not grant, in request order.
    /// Identity scopes are never reported (they have no checkbox on the
    /// consent page and Google may spell them differently).
    static func missing(_ requested: [String], in granted: Set<String>) -> [String] {
        requested.filter { !identity.contains($0) && !granted.contains($0) }
    }
}

// MARK: - Features behind each scope

/// A product area that needs one OAuth scope. Used to tell the user what stays
/// off when they untick a checkbox on the consent page (plan R4).
enum GoogleScopeFeature: String, CaseIterable, Sendable {
    case firebaseProjects
    case cloudMessaging
    case playApps
    case playContent

    /// The scope this feature needs.
    var scope: String {
        switch self {
        case .firebaseProjects: return GoogleOAuthScope.firebase
        case .cloudMessaging:   return GoogleOAuthScope.firebaseMessaging
        case .playApps:         return GoogleOAuthScope.playDeveloperReporting
        case .playContent:      return GoogleOAuthScope.androidPublisher
        }
    }

    var displayName: String {
        switch self {
        case .firebaseProjects: return String(localized: "Firebase projects and apps")
        case .cloudMessaging:   return String(localized: "Cloud Messaging")
        case .playApps:         return String(localized: "Google Play app list")
        case .playContent:      return String(localized: "Google Play releases, reviews and users")
        }
    }

    /// The features of `provider` that `missingScopes` turns off, in display order.
    static func disabled(by missingScopes: [String], for provider: ProviderType) -> [GoogleScopeFeature] {
        features(for: provider).filter { missingScopes.contains($0.scope) }
    }

    /// The features an account of `provider` signed in with Google uses.
    static func features(for provider: ProviderType) -> [GoogleScopeFeature] {
        switch provider {
        case .firebase:   return [.firebaseProjects, .cloudMessaging]
        case .googlePlay: return [.playApps, .playContent]
        case .apple:      return []
        }
    }

    /// The scopes without which `provider` can't list anything to add: the
    /// picker has nothing to show and no account can be created.
    static func requiredScopes(for provider: ProviderType) -> [String] {
        switch provider {
        case .firebase:   return [GoogleOAuthScope.firebase]
        case .googlePlay: return [GoogleOAuthScope.playDeveloperReporting]
        case .apple:      return []
        }
    }
}
