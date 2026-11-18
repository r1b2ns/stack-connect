import Foundation
import StackProtocols

/// A backend sink for analytics events (log, vendor SDK, own endpoint, …).
/// `AnalyticsService` owns the opt-out gate, so providers never check the
/// setting themselves: anything they receive is meant to be sent.
protocol AnalyticsProvider: Sendable {
    /// Hands `event` (already enriched with the standard parameters) to the backend.
    func send(_ event: AnalyticsEvent)

    /// Pushes any buffered events out. Called right after the opt-out event.
    func flush() async

    /// Clears vendor-side identifiers/state. Called when analytics is disabled.
    func reset()

    /// Sets (or, with `nil`, clears) a user property: a low-cardinality,
    /// PII-free segment value (e.g. `account_count=2`) the backend attaches to
    /// the events that follow. Like `send`, only called while enabled.
    func setUserProperty(_ value: String?, forName name: String)

    /// Turns the vendor SDK's own collection on or off. Called on launch with the
    /// current setting, on opt-in (before `analytics_enabled` is sent) and on
    /// opt-out (after `analytics_disabled` was sent and `flush` finished).
    /// Providers without a vendor-side switch keep the default no-op.
    func setCollectionEnabled(_ enabled: Bool)

    /// Records a handled, non-fatal error (crash reporters). Receives a
    /// scrubbed `NSError` only — domain, code and `error_category`, never the
    /// original `userInfo` or message (`AnalyticsService.recordNonFatal`).
    /// Like `send`, only called while enabled. Default: ignored.
    func recordNonFatal(_ error: NSError)
}

extension AnalyticsProvider {
    func setCollectionEnabled(_ enabled: Bool) {}
    func recordNonFatal(_ error: NSError) {}
}

/// Provider that only writes events to the unified log. Used until a vendor is
/// chosen, and kept in DEBUG to inspect events in Console.
struct LogAnalyticsProvider: AnalyticsProvider {

    func send(_ event: AnalyticsEvent) {
        Log.print.info("[Analytics] \(Self.format(event))")
    }

    func flush() async {}

    func reset() {}

    func setUserProperty(_ value: String?, forName name: String) {
        Log.print.info("[Analytics] \(Self.formatUserProperty(name: name, value: value))")
    }

    /// `user_property name=value` (`<nil>` when cleared).
    static func formatUserProperty(name: String, value: String?) -> String {
        "user_property \(name)=\(value ?? "<nil>")"
    }

    /// `name {key=value, …}` with keys sorted, so log lines are deterministic.
    static func format(_ event: AnalyticsEvent) -> String {
        let params = event.parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
            .joined(separator: ", ")
        return "\(event.name) {\(params)}"
    }
}
