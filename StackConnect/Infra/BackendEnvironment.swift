import Foundation

/// Composition root for the backends the app talks to.
///
/// Every connection, ViewModel and service reads its backend from here through
/// a default argument, so tests keep injecting their own mocks and nothing else
/// needs to know which backend is live. The values are the production ones; the
/// DEBUG fake data mode replaces them **once, at launch, before any screen is
/// built** (`FakeDataBootstrap.install`) — they are never mutated afterwards,
/// which is what makes the `nonisolated(unsafe)` storage safe.
enum BackendEnvironment {

    /// Rust core providers for App Store Connect and Google Play.
    nonisolated(unsafe) static var coreProviders: any CoreProviderMaking = RustCoreProviderFactory()

    /// Firebase REST API providers.
    nonisolated(unsafe) static var firebaseProviders: any FirebaseProviderMaking = LiveFirebaseProviderFactory()

    /// App Store rating summary shown above an app's reviews (public iTunes Lookup API).
    nonisolated(unsafe) static var ratingSummaryFetcher: any AppStoreRatingSummaryFetching = ITunesRatingSummaryFetcher()
}
