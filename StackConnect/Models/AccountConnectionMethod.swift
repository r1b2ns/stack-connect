import SwiftUI

/// A way to connect a new account in Add Account: what the method chooser
/// offers as cards and the connection guide describes.
///
/// Which methods a provider offers depends on the build (`available(for:…)`):
/// App Store Connect always has the API key, plus "Sign in with email and
/// password" while `appleIdSignIn` is ON; Firebase (and Google Play) always
/// have the service account key, plus "Sign in with Google" while
/// `googleSignIn` is ON and the build has an OAuth client ID.
///
/// Copy rules (App Review): a method is only ever described on its own
/// provider's path, with that provider's name, and the email and password
/// method never looks like the "Sign in with Apple" button (no Apple logo).
enum AccountConnectionMethod: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// App Store Connect API key (`.p8` file, Key ID, Issuer ID).
    case apiKey
    /// App Store Connect email and password, plus a two-factor code (flag
    /// `appleIdSignIn`): the Apple ID web session.
    case appleIdSignIn
    /// "Sign in with Google" (Firebase, Google Play; flag `googleSignIn`).
    case googleSignIn
    /// A Google service account JSON key file (Firebase, Google Play).
    case serviceAccount

    var id: String { rawValue }

    /// The methods `provider` offers, in display order. The key-based method
    /// comes first for App Store Connect (the official API), and Google
    /// sign-in first for Firebase and Google Play (their primary path).
    /// - Parameters:
    ///   - appleIdSignIn: "Sign in with email and password" is available.
    ///   - googleSignIn: "Sign in with Google" is available.
    static func available(
        for provider: ProviderType,
        appleIdSignIn: Bool,
        googleSignIn: Bool
    ) -> [AccountConnectionMethod] {
        switch provider {
        case .apple:
            return appleIdSignIn ? [.apiKey, .appleIdSignIn] : [.apiKey]
        case .firebase, .googlePlay:
            return googleSignIn ? [.googleSignIn, .serviceAccount] : [.serviceAccount]
        }
    }

    // MARK: - Display

    /// The chooser card's title.
    var title: String {
        switch self {
        case .apiKey:         return String(localized: "Use an API key", comment: "Add Account method chooser: card that connects App Store Connect with an API key (.p8).")
        case .appleIdSignIn:  return String(localized: "Sign in with email and password", comment: "Add Account: the App Store Connect option that signs in with the Apple ID email and password plus a two-factor code. Must not read as Apple's \"Sign in with Apple\" button.")
        case .googleSignIn:   return String(localized: "Sign in with Google")
        case .serviceAccount: return String(localized: "Use a service account key", comment: "Add Account method chooser: card that connects with a Google service account JSON key file.")
        }
    }

    /// One or two sentences under the title: what the method needs and what
    /// it gives. Names only `provider`.
    func summary(for provider: ProviderType) -> String {
        switch self {
        case .apiKey:
            return String(localized: "Add an App Store Connect API key: its .p8 file, Key ID and Issuer ID. Works with every feature, including Analytics Reports.",
                          comment: "Add Account method chooser and connection guide: what the API key method needs.")
        case .appleIdSignIn:
            return String(localized: "Use the email and password you sign in to App Store Connect with, plus a two-factor code. No API key needed; Analytics Reports aren't available.",
                          comment: "Add Account method chooser and connection guide: what the email and password method needs.")
        case .googleSignIn:
            return String(localized: "Sign in on Google's page with the account you use for \(provider.displayName), then pick what to add. No key file needed.",
                          comment: "Add Account method chooser and connection guide: the Google sign-in method. The placeholder is the service being connected, e.g. Firebase.")
        case .serviceAccount:
            return String(localized: "Add a service account's JSON key file. Suited to shared team accounts and automation.",
                          comment: "Add Account method chooser and connection guide: what the service account method needs.")
        }
    }

    /// The navigation title of the method's form when it is pushed from the
    /// chooser (the email and password method pushes its own screens).
    var formTitle: String {
        switch self {
        case .apiKey:         return String(localized: "API Key")
        case .appleIdSignIn:  return title
        case .googleSignIn:   return String(localized: "Google Account")
        case .serviceAccount: return String(localized: "Service Account Key")
        }
    }

    /// A neutral glyph: never the Apple logo, whatever the method.
    var systemImage: String {
        switch self {
        case .apiKey:         return "key.fill"
        case .appleIdSignIn:  return "person.badge.key.fill"
        case .googleSignIn:   return "person.crop.circle.badge.checkmark"
        case .serviceAccount: return "curlybraces.square.fill"
        }
    }
}
