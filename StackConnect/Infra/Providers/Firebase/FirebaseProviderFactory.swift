import Foundation
import APIProviderFirebase

/// Builds the `APIProviderFirebase` a Firebase screen talks to.
///
/// The one seam between the Firebase ViewModels and the Firebase REST APIs.
/// Production uses `LiveFirebaseProviderFactory` (URLSession + service-account
/// OAuth); the DEBUG fake data mode serves the APIs in-process instead
/// (`BackendEnvironment`, `FakeDataBootstrap`).
protocol FirebaseProviderMaking: Sendable {
    func makeProvider(configuration: FirebaseConfiguration) -> APIProviderFirebase
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
}

/// The real Firebase APIs.
struct LiveFirebaseProviderFactory: FirebaseProviderMaking {
    func makeProvider(configuration: FirebaseConfiguration) -> APIProviderFirebase {
        APIProviderFirebase(configuration: configuration)
    }
}
