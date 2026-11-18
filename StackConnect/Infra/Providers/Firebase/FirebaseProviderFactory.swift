import Foundation
import APIProviderFirebase
import StackProtocols

/// Builds the `APIProviderFirebase` a Firebase screen talks to.
///
/// The one seam between the Firebase ViewModels and the Firebase REST APIs.
/// Production uses `LiveFirebaseProviderFactory` (URLSession + service-account
/// OAuth, or the user's own Google sign-in); the DEBUG fake data mode serves
/// the APIs in-process instead (`BackendEnvironment`, `FakeDataBootstrap`).
protocol FirebaseProviderMaking: Sendable {
    /// A provider authenticated with a service account.
    func makeProvider(configuration: FirebaseConfiguration) -> APIProviderFirebase
    /// A provider authenticated by `authenticator` alone (a Google sign-in login).
    func makeProvider(authenticator: RequestAuthenticating) -> APIProviderFirebase
}

extension FirebaseProviderMaking {

    /// Parses the stored service-account JSON and builds a provider for it, or
    /// `nil` when the JSON or its private key is invalid.
    func makeProvider(serviceAccountJSON: String) -> APIProviderFirebase? {
        guard let jsonData = serviceAccountJSON.data(using: .utf8),
              let configuration = try? FirebaseConfiguration(serviceAccountJSON: jsonData) else {
            return nil
        }
        return makeProvider(configuration: configuration)
    }

    /// The provider for an account's stored credentials, whichever way it
    /// authenticates (`GoogleCredentialSource`): the service-account JSON, or
    /// the user's Google sign-in through `tokens` (default: the app's
    /// `GoogleAuthService`). `nil` when a service-account JSON is unusable.
    @MainActor
    func makeProvider(
        credentials: FirebaseCredentials,
        tokens: (any GoogleAccessTokenProviding)? = nil
    ) -> APIProviderFirebase? {
        switch credentials.source {
        case .serviceAccount(let json):
            return makeProvider(serviceAccountJSON: json)
        case .googleSignIn(let loginId):
            return makeProvider(authenticator: GoogleSignInRequestAuthenticator(
                loginId: loginId,
                tokens: tokens ?? GoogleAuthService.shared
            ))
        }
    }
}

/// The real Firebase APIs.
struct LiveFirebaseProviderFactory: FirebaseProviderMaking {
    func makeProvider(configuration: FirebaseConfiguration) -> APIProviderFirebase {
        APIProviderFirebase(configuration: configuration)
    }

    func makeProvider(authenticator: RequestAuthenticating) -> APIProviderFirebase {
        APIProviderFirebase(authenticator: authenticator)
    }
}
