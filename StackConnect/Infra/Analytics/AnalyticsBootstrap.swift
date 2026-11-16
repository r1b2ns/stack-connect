import FirebaseCore
import Foundation

/// Decides which analytics providers this build ships with.
///
/// Firebase is optional: `GoogleService-Info.plist` is git-ignored, so open
/// source checkouts and CI build without it. When the file is absent (or the app
/// is hosting unit tests) only the log provider is used.
enum AnalyticsBootstrap {

    static let firebaseConfigResource = "GoogleService-Info"

    /// Configures Firebase when possible and returns the providers to use.
    /// Called once, by `AnalyticsService.shared`.
    @MainActor
    static func makeDefaultProviders(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> [any AnalyticsProvider] {
        var providers: [any AnalyticsProvider] = []

        if shouldUseFirebase(bundle: bundle, processInfo: processInfo) {
            // Not guarded with `FirebaseApp.app() == nil`: that getter logs
            // I-COR000003 when no app exists yet. This runs once, from
            // `AnalyticsService.shared`'s initialiser.
            FirebaseApp.configure()
            providers.append(FirebaseAnalyticsProvider())
            Log.print.info("[Analytics] Firebase provider configured")
        } else {
            Log.print.info("[Analytics] Firebase not configured (no \(firebaseConfigResource).plist or running tests): using the log provider only")
        }

        #if DEBUG
        providers.append(LogAnalyticsProvider())
        #else
        if providers.isEmpty {
            providers.append(LogAnalyticsProvider())
        }
        #endif
        return providers
    }

    /// Firebase is used only when its config file is bundled, and never while
    /// the app is the host of a unit-test run (tests must not send events).
    static func shouldUseFirebase(bundle: Bundle, processInfo: ProcessInfo) -> Bool {
        guard processInfo.environment["XCTestConfigurationFilePath"] == nil else { return false }
        #if DEBUG
        // Demo sessions on fake data must not reach the product's analytics.
        guard !FakeDataMode(arguments: processInfo.arguments, environment: processInfo.environment).isEnabled else { return false }
        #endif
        return bundle.path(forResource: firebaseConfigResource, ofType: "plist") != nil
    }
}
