import FirebaseCrashlytics
import Foundation
import StackProtocols

/// The slice of the Crashlytics SDK the app uses. A seam so the provider's
/// gating and scrubbing are unit tested without a configured `FirebaseApp`.
protocol CrashlyticsClient: Sendable {
    func setCollectionEnabled(_ enabled: Bool)
    func record(_ error: NSError)
}

/// `Crashlytics.crashlytics()`. Only built after `FirebaseApp.configure()`.
struct FirebaseCrashlyticsClient: CrashlyticsClient {
    func setCollectionEnabled(_ enabled: Bool) {
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }

    func record(_ error: NSError) {
        Crashlytics.crashlytics().record(error: error)
    }
}

/// Crash reporting as an `AnalyticsProvider`, so the analytics opt-out covers
/// it with no extra wiring: `AnalyticsService.applyCollectionSetting()` (launch)
/// and `setEnabled(_:)` (Settings) switch Crashlytics collection on and off
/// exactly like Analytics collection, and non-fatals only arrive while enabled.
///
/// Collection starts disabled (`FirebaseCrashlyticsCollectionEnabled = NO` in
/// Info.plist): a crash report of an opted-out user is never uploaded.
///
/// Events are not forwarded (no breadcrumbs): Crashlytics only receives crashes
/// and the scrubbed non-fatals of `AnalyticsService.recordNonFatal`.
struct CrashlyticsProvider: AnalyticsProvider {

    private let client: CrashlyticsClient

    init(client: CrashlyticsClient = FirebaseCrashlyticsClient()) {
        self.client = client
    }

    func send(_ event: AnalyticsEvent) {}

    func flush() async {}

    /// Nothing to reset: no user identifier or custom key is ever set.
    func reset() {}

    func setUserProperty(_ value: String?, forName name: String) {}

    func setCollectionEnabled(_ enabled: Bool) {
        client.setCollectionEnabled(enabled)
    }

    func recordNonFatal(_ error: NSError) {
        client.record(error)
    }
}
