import FirebaseAnalytics
import Foundation
import StackProtocols

/// Sends events to Google Analytics for Firebase. Only built by
/// `AnalyticsBootstrap` after `FirebaseApp.configure()` succeeded.
///
/// Kept deliberately thin: every mapping and limit lives in the pure
/// `FirebaseAnalyticsPayload`, so this type only forwards to the SDK.
///
/// Collection starts disabled (`FIREBASE_ANALYTICS_COLLECTION_ENABLED = NO` in
/// Info.plist) and is turned on through `setCollectionEnabled(_:)` only when the
/// user setting is ON, so an opted-out user never sends anything, not even
/// `first_open`.
struct FirebaseAnalyticsProvider: AnalyticsProvider {

    func send(_ event: AnalyticsEvent) {
        guard let payload = FirebaseAnalyticsPayload.make(from: event) else { return }
        Analytics.logEvent(payload.name, parameters: payload.parameters.isEmpty ? nil : payload.parameters)
    }

    func setUserProperty(_ value: String?, forName name: String) {
        guard let property = FirebaseAnalyticsPayload.userProperty(name: name, value: value) else { return }
        Analytics.setUserProperty(property.value, forName: property.name)
    }

    /// Firebase has no public flush: events are queued and uploaded by the SDK.
    func flush() async {}

    /// Intentionally a no-op. `Analytics.resetAnalyticsData()` would delete the
    /// queued, not yet uploaded `analytics_disabled` event, and the product
    /// requires that last event to be sent. Collection is stopped through
    /// `setCollectionEnabled(false)`, which `AnalyticsService` calls on opt-out.
    func reset() {}

    func setCollectionEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }
}
