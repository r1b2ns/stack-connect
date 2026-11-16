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

    /// Turns the vendor SDK's own collection on or off. Called on launch with the
    /// current setting, on opt-in (before `analytics_enabled` is sent) and on
    /// opt-out (after `analytics_disabled` was sent and `flush` finished).
    /// Providers without a vendor-side switch keep the default no-op.
    func setCollectionEnabled(_ enabled: Bool)
}

extension AnalyticsProvider {
    func setCollectionEnabled(_ enabled: Bool) {}
}

/// Provider that only writes events to the unified log. Used until a vendor is
/// chosen, and kept in DEBUG to inspect events in Console.
struct LogAnalyticsProvider: AnalyticsProvider {

    func send(_ event: AnalyticsEvent) {
        Log.print.info("[Analytics] \(Self.format(event))")
    }

    func flush() async {}

    func reset() {}

    /// `name {key=value, …}` with keys sorted, so log lines are deterministic.
    static func format(_ event: AnalyticsEvent) -> String {
        let params = event.parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
            .joined(separator: ", ")
        return "\(event.name) {\(params)}"
    }
}
